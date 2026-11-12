# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

"""Bounded sequential HTTP measurements using the controller's golden evaluator."""

import argparse
import asyncio
import hashlib
import json
import os
import re
import time
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import urlparse
from uuid import uuid4

import aiohttp
from pydantic import ValidationError

from .contracts import Answer
from .evaluation import GoldenCase, check
from .experiment import RequestMeasurement, RunMeasurement


def record_response(
    case: GoldenCase,
    body: object,
    *,
    http_status: int,
    session_hash: str,
    experiment_hash: str,
    elapsed_ms: float,
) -> RequestMeasurement:
    record = RequestMeasurement(
        case_id=case.id,
        session_hash=session_hash,
        elapsed_ms=elapsed_ms,
        http_status=http_status,
        answer_status=None,
        trace_id=None,
        failures=[],
        agent_calls=[],
        model_usage=[],
    )
    try:
        answer = Answer.model_validate(body)
    except ValidationError:
        record.failures = ["response-contract"]
        return record
    record.failures = check(case, answer)
    record.answer_status = answer.answer_status
    record.trace_id = answer.evidence.trace_id
    record.agent_calls = answer.evidence.agent_calls
    record.model_usage = answer.evidence.model_usage
    if http_status != 200:
        record.failures.append("http-status")
    if (
        answer.evidence.model_mode != "azure-openai"
        or answer.evidence.session_hash != session_hash
        or answer.evidence.experiment_hash != experiment_hash
        or not answer.evidence.trace_id
        or not answer.evidence.model_usage
    ):
        record.failures.append("live-evidence")
    return record


async def collect(args: argparse.Namespace) -> None:
    if (
        not re.fullmatch(r"h09-[0-9]{1,12}", args.experiment_id)
        or args.application_name
        != f"ca-dto-x-{args.experiment_id.removeprefix('h09-')}-{args.variant[0]}"
    ):
        raise ValueError("The target app must belong to this exact experiment run and variant.")
    endpoint = urlparse(args.base_uri)
    if (
        endpoint.scheme != "https"
        or not endpoint.hostname
        or not endpoint.hostname.startswith(args.application_name + ".")
        or not endpoint.hostname.endswith(".eastus2.azurecontainerapps.io")
        or endpoint.port not in {None, 443}
        or endpoint.username
        or endpoint.password
        or endpoint.path not in {"", "/"}
        or endpoint.query
        or endpoint.fragment
    ):
        raise ValueError("The target must be the verified temporary sample app HTTPS endpoint.")
    token = os.environ.get("SAMPLE_API_TOKEN", "")
    if len(token) < 32:
        raise ValueError("Supply the API token privately through the process environment.")
    question_bytes = args.questions.read_bytes()
    cases = [GoldenCase.model_validate(value) for value in json.loads(question_bytes)]
    if len(cases) != 7 or len({case.id for case in cases}) != 7:
        raise ValueError("The approved seven-question schedule is required.")
    experiment_id = args.experiment_id + ("-warmup" if args.warmup else "")
    experiment_hash = hashlib.sha256(experiment_id.encode()).hexdigest()
    if args.warmup:
        cases = [next(case for case in cases if case.id == "inventory-below-reorder")]
    start = datetime.now(UTC)
    deadline = time.monotonic() + (60 if args.warmup else 600)
    measurements = []
    last_start = time.monotonic() - 60
    async with aiohttp.ClientSession() as session:
        for case in cases:
            await asyncio.sleep(max(0, last_start + 60 - time.monotonic()))
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            session_id = str(uuid4())
            session_hash = hashlib.sha256(session_id.encode()).hexdigest()
            body: object = None
            status = 0
            last_start = time.monotonic()
            try:
                async with session.post(
                    args.base_uri.rstrip("/") + "/api/questions",
                    headers={"x-sample-token": token},
                    json={
                        "question": case.question,
                        "sessionId": session_id,
                        "experimentId": experiment_id,
                        "variant": args.variant,
                    },
                    timeout=aiohttp.ClientTimeout(total=min(230, remaining)),
                    allow_redirects=False,
                ) as response:
                    status = response.status
                    body = await response.json(content_type=None)
            except (aiohttp.ClientError, TimeoutError, ValueError):
                # Persist the failed request, never its body or provider exception.
                body = None
            measurements.append(
                record_response(
                    case,
                    body,
                    http_status=status,
                    session_hash=session_hash,
                    experiment_hash=experiment_hash,
                    elapsed_ms=(time.monotonic() - last_start) * 1000,
                )
            )
    if args.warmup:
        await asyncio.sleep(max(0, deadline - time.monotonic()))
    record = RunMeasurement(
        experiment_id=experiment_id,
        variant=args.variant,
        repetition=args.repetition,
        revision=args.revision,
        image=args.image,
        conditions_hash=args.conditions_hash,
        questions_hash=hashlib.sha256(question_bytes).hexdigest(),
        start_utc=start,
        end_utc=datetime.now(UTC),
        requests=measurements,
    )
    args.output.write_text(record.model_dump_json(by_alias=True, indent=2) + "\n")
    if len(measurements) != len(cases):
        raise RuntimeError("The approved question schedule exceeded its measurement window.")
    if args.warmup and any(request.failures for request in measurements):
        raise RuntimeError("Warm-up did not pass the live golden answer contract.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-uri", required=True)
    parser.add_argument("--application-name", required=True)
    parser.add_argument("--questions", required=True, type=Path)
    parser.add_argument("--experiment-id", required=True)
    parser.add_argument("--variant", choices=["baseline", "candidate"], required=True)
    parser.add_argument("--repetition", type=int, choices=[1, 2], required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--image", required=True)
    parser.add_argument("--conditions-hash", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--warmup", action="store_true")
    asyncio.run(collect(parser.parse_args()))


if __name__ == "__main__":
    main()
