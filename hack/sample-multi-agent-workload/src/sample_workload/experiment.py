# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

"""Evaluate retained experiment evidence without calling Azure or a model."""

import argparse
import hashlib
import json
import math
import re
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from typing import Literal, TypedDict

from pydantic import Field, field_validator

from .contracts import Contract, ModelUsage
from .evaluation import GoldenCase


class RunAnalysis(TypedDict):
    variant: str
    repetition: int
    revision: str
    image: str
    conditionsHash: str
    requestCount: int
    successfulAnswers: int
    expectedNonAnswers: int
    qualityPercent: float
    errorRatePercent: float
    p95LatencyMs: float | None
    throughputPerSecond: float | None
    tokens: dict[str, int | None]
    knownTokenSubtotal: dict[str, int]
    modelCalls: int
    unpricedCalls: int
    priceCoveragePercent: float
    knownPricedSubtotalUsd: str
    estimatedModelCostUsd: str | None
    costPerSuccessfulAnswerUsd: str | None
    costPer1000SuccessfulAnswersUsd: str | None
    evidenceComplete: bool
    problems: list[str]


class Comparison(TypedDict):
    version: int
    decision: str
    evidenceComplete: bool
    cleanupSucceeded: bool
    candidateChangeVerified: bool
    costBasis: str
    runs: list[RunAnalysis]
    baselineCostSpreadPercent: str | None
    costChangePercent: str | None
    problems: list[str]
    failedGuardrails: list[str]
    limitations: list[str]


class RequestMeasurement(Contract):
    case_id: str = Field(alias="caseId")
    session_hash: str = Field(alias="sessionHash", pattern=r"^[a-f0-9]{64}$")
    elapsed_ms: float = Field(alias="elapsedMs", ge=0, allow_inf_nan=False)
    http_status: int = Field(alias="httpStatus", ge=0, le=599)
    answer_status: str | None = Field(alias="answerStatus")
    trace_id: str | None = Field(alias="traceId")
    failures: list[str]
    agent_calls: list[str] = Field(alias="agentCalls", max_length=4)
    model_usage: list[ModelUsage] = Field(alias="modelUsage", max_length=4)


class SpanMeasurement(Contract):
    name: str = Field(alias="Name")
    timestamp: datetime = Field(alias="TimeGenerated")
    revision: str = Field(alias="AppVersion")
    operation_id: str = Field(alias="OperationId")
    session_hash: str = Field(alias="SessionId")
    span_id: str = Field(alias="Id")
    parent_id: str | None = Field(alias="ParentId")
    properties: dict[str, object] = Field(alias="Properties")

    @field_validator("properties", mode="before")
    @classmethod
    def parse_properties(cls, value: object) -> object:
        return json.loads(value) if isinstance(value, str) else value

    @field_validator("timestamp")
    @classmethod
    def require_utc_offset(cls, value: datetime) -> datetime:
        if value.utcoffset() is None:
            raise ValueError("Span timestamps require an explicit UTC offset.")
        return value


class RunMeasurement(Contract):
    version: Literal[1] = 1
    experiment_id: str = Field(alias="experimentId")
    variant: Literal["baseline", "candidate"]
    repetition: int = Field(ge=1, le=2)
    revision: str = Field(pattern=r"^[a-f0-9]{40}$")
    image: str = Field(pattern=r"^crftkdtohacksae46[.]azurecr[.]io/.+@sha256:[a-f0-9]{64}$")
    conditions_hash: str = Field(alias="conditionsHash", pattern=r"^[a-f0-9]{64}$")
    questions_hash: str = Field(alias="questionsHash", pattern=r"^[a-f0-9]{64}$")
    start_utc: datetime = Field(alias="startUtc")
    end_utc: datetime = Field(alias="endUtc")
    requests: list[RequestMeasurement] = Field(max_length=7)
    telemetry: list[SpanMeasurement] = Field(default_factory=list, max_length=200)

    @field_validator("start_utc", "end_utc")
    @classmethod
    def require_utc_offset(cls, value: datetime) -> datetime:
        if value.utcoffset() is None:
            raise ValueError("Measurement windows require an explicit UTC offset.")
        return value


def utc(value: object) -> datetime:
    if not isinstance(value, str):
        raise ValueError("An ISO 8601 timestamp is required.")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.utcoffset() is None:
        raise ValueError("A timestamp must include its UTC offset.")
    return parsed


def token_count(value: object) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value if value >= 0 else None
    if isinstance(value, str) and re.fullmatch(r"\d+", value):
        return int(value)
    return None


def validate_definition(definition: dict[str, object]) -> dict[str, str]:
    expected: dict[str, object] = {
        "version": 1,
        "adapter": "sample-multi-agent",
        "workloadUnit": {"name": "successful evaluated answers", "quantity": 1000},
        "scope": {
            "subscriptionId": "6e87e78d-fe02-4f01-bd7b-4f2157eabd5a",
            "resourceGroupPrefix": "ftk-dto-hack-s-ae46",
            "region": "eastus2",
        },
        "load": {
            "testFile": "../tests/evaluation/questions.json",
            "warmupMinutes": 1,
            "durationMinutes": 10,
            "virtualUsers": 1,
            "baselineRepetitions": 2,
            "requestIntervalSeconds": 60,
        },
        "guardrails": {
            "answerQualityPercent": {"minimum": 100},
            "errorRatePercent": {"maximum": 0},
            "p95LatencyRegressionPercent": {"maximum": 20},
        },
        "cost": {
            "currency": "USD",
            "pricingSource": "finops-hub",
            "requiredMeters": ["input", "cachedInput", "output"],
            "minimumImprovementPercent": 5,
        },
        "cleanup": {"maximumLifetimeMinutes": 90},
    }
    if any(definition.get(key) != value for key, value in expected.items()):
        raise ValueError("Preserve the approved sample policy and all guardrails.")
    variants = definition.get("variants")
    if not isinstance(variants, dict) or set(variants) != {"baseline", "candidate"}:
        raise ValueError("Exactly two variant revisions are required.")
    revisions: dict[str, str] = {}
    for variant, value in variants.items():
        if (
            not isinstance(value, dict)
            or set(value) != {"ref"}
            or not isinstance(value.get("ref"), str)
            or not re.fullmatch(r"[a-f0-9]{40}", value["ref"])
        ):
            raise ValueError("Variant refs must be exact commit SHAs.")
        revisions[variant] = value["ref"]
    if revisions["baseline"] == revisions["candidate"]:
        raise ValueError("Different exact revisions are required.")
    return revisions


def price_rows(
    context: dict[str, object], now: datetime
) -> tuple[dict[str, dict[str, object]], list[str]]:
    """Keep unknown or invalid pricing explicit, not zero."""
    problems = []
    rates: dict[str, dict[str, object]] = {}
    try:
        scope = context["dataScope"]
        freshness = context["freshness"]
        data = context["data"]
        evidence = context["evidence"]
        if not isinstance(scope, dict) or not isinstance(freshness, dict):
            raise ValueError("Price scope/freshness is missing.")
        if (
            context.get("tool") != "get_current_pricing"
            or context.get("source") != "finops-hub"
            or scope.get("model") != "gpt-5-mini"
            or scope.get("region") != "eastus2"
            or scope.get("currency") != "USD"
            or scope.get("deploymentSku") != "GlobalStandard"
            or not isinstance(evidence, list)
            or not evidence
            or not isinstance(data, dict)
            or not isinstance(data.get("rows"), list)
        ):
            raise ValueError("Price scope, currency, or provenance is invalid.")
        retrieved = utc(freshness["pricingAsOf"])
        if not timedelta(0) <= now - retrieved <= timedelta(days=7):
            raise ValueError("Required prices are stale or future-dated.")
        rows = data["rows"]
        if len(rows) != 3:
            raise ValueError("Exactly three required model prices are needed.")
        meter_ids = set()
        for row in rows:
            if not isinstance(row, dict):
                raise ValueError("Price row is invalid.")
            direction = str(row.get("Direction"))
            amount = Decimal(str(row.get("Price")))
            if (
                direction not in {"input", "cachedInput", "output"}
                or direction in rates
                or not row.get("MeterId")
                or row["MeterId"] in meter_ids
                or row.get("Currency") != "USD"
                or row.get("Offer") != "PUBLIC-RETAIL"
                or row.get("Unit") != "1M"
                or row.get("BlockSize") != 1_000_000
                or row.get("Region") != "US East 2"
                or not amount.is_finite()
                or amount <= 0
                or utc(row["EffectiveStart"]) > now
            ):
                raise ValueError("Required price identity, units, currency, or rate is invalid.")
            if row.get("EffectiveEnd") and utc(row["EffectiveEnd"]) <= now:
                raise ValueError("A required model price has expired.")
            rates[direction] = row
            meter_ids.add(row["MeterId"])
    except (KeyError, ValueError, TypeError, ArithmeticError):
        rates = {}
        problems.append("Required pricing is missing, invalid, stale, or incompatible.")
    return rates, problems


def analyze_run(
    run: RunMeasurement,
    cases: list[GoldenCase],
    rates: dict[str, dict[str, object]],
) -> RunAnalysis:
    problems: list[str] = []
    expected_cases = {case.id: case for case in cases}
    actual_cases = [request.case_id for request in run.requests]
    if sorted(actual_cases) != sorted(expected_cases):
        problems.append("The measured question schedule is incomplete or duplicated.")
    sessions = [request.session_hash for request in run.requests]
    if len(set(sessions)) != len(sessions):
        problems.append("Request sessions are duplicated.")
    if not timedelta(0) < run.end_utc - run.start_utc <= timedelta(minutes=11):
        problems.append("The measurement window is invalid.")
    quality_passed = sum(not request.failures for request in run.requests)
    successful = sum(
        not request.failures
        and request.http_status == 200
        and request.answer_status == "answered"
        and expected_cases.get(request.case_id) is not None
        and expected_cases[request.case_id].expected_status == "answered"
        for request in run.requests
    )
    errors = sum(request.http_status != 200 for request in run.requests)
    if not successful:
        problems.append("There are zero successful evaluated answers.")
    trace_ids = [request.trace_id for request in run.requests if request.trace_id]
    if len(trace_ids) != len(set(trace_ids)):
        problems.append("Response trace identifiers are duplicated.")
    span_ids = [span.span_id for span in run.telemetry]
    if len(span_ids) != len(set(span_ids)):
        problems.append("Telemetry span identifiers are duplicated.")
    experiment_hash = hashlib.sha256(run.experiment_id.encode()).hexdigest()
    request_by_session = {request.session_hash: request for request in run.requests}
    for span in run.telemetry:
        request = request_by_session.get(span.session_hash)
        if (
            request is None
            or span.revision != run.revision
            or not run.start_utc <= span.timestamp <= run.end_utc
            or span.properties.get("experiment.id") != experiment_hash
            or span.properties.get("session.id") != span.session_hash
            or span.properties.get("optimization.variant") != run.variant
            or (request.trace_id and span.operation_id != request.trace_id)
        ):
            problems.append("Telemetry attribution, revision, or measurement window is invalid.")
    model_spans = [span for span in run.telemetry if span.name == "gen_ai.chat"]
    subtotal = Decimal(0)
    totals = {"input": 0, "cachedInput": 0, "output": 0}
    unknown_quantities: set[str] = set()
    priced = 0
    seen = set()
    for span in model_spans:
        if span.span_id in seen:
            continue
        seen.add(span.span_id)
        fields = span.properties
        quantities = {
            "input": token_count(fields.get("gen_ai.usage.input_tokens")),
            "cachedInput": token_count(fields.get("gen_ai.usage.cache_read.input_tokens")),
            "output": token_count(fields.get("gen_ai.usage.output_tokens")),
        }
        for direction, quantity in quantities.items():
            if quantity is None:
                unknown_quantities.add(direction)
            else:
                totals[direction] += quantity
        model = re.sub(r"-\d{4}-\d{2}-\d{2}$", "", str(fields.get("gen_ai.response.model")))
        if any(value is None for value in quantities.values()):
            problems.append("A model call has unknown or invalid token consumption.")
            continue
        input_tokens = quantities["input"]
        cached_tokens = quantities["cachedInput"]
        output_tokens = quantities["output"]
        assert input_tokens is not None and cached_tokens is not None and output_tokens is not None
        parents = [parent for parent in run.telemetry if parent.span_id == span.parent_id]
        if (
            cached_tokens > input_tokens
            or len(parents) != 1
            or parents[0].operation_id != span.operation_id
            or parents[0].session_hash != span.session_hash
        ):
            unknown_quantities.update(quantities)
            problems.append("Cached-token counts or model parent attribution are invalid.")
            continue
        if model != "gpt-5-mini" or len(rates) != 3:
            problems.append("A required model call is unpriced.")
            continue
        if any(
            span.timestamp < utc(row["EffectiveStart"])
            or (row.get("EffectiveEnd") and span.timestamp >= utc(row["EffectiveEnd"]))
            for row in rates.values()
        ):
            problems.append("A price is not effective at the model call time.")
            continue
        quantities["input"] = input_tokens - cached_tokens
        subtotal += sum(
            Decimal(str(quantities[direction]))
            * Decimal(str(rates[direction]["Price"]))
            / Decimal(1_000_000)
            for direction in quantities
        )
        priced += 1
    for request in run.requests:
        spans = [span for span in model_spans if span.session_hash == request.session_hash]
        roots = [
            span
            for span in run.telemetry
            if span.name == "coordinator.run" and span.session_hash == request.session_hash
        ]
        if len(roots) != 1 or not spans:
            problems.append("A request is missing its coordinator/model telemetry.")
        expected_usage = request.model_usage
        roles = [str(span.properties.get("agent.name")) for span in spans]
        if len(roles) != len(set(roles)) or len(spans) != len(expected_usage):
            problems.append("Provider usage and measured model spans do not reconcile.")
            continue
        measurements = {str(span.properties.get("agent.name")): span for span in spans}
        if len(expected_usage) != len(request.agent_calls):
            problems.append("Provider agent-call attribution is incomplete.")
            continue
        for role, usage in zip(request.agent_calls, expected_usage, strict=True):
            measured = measurements.get(role)
            if measured is None or (
                measured.properties.get("gen_ai.response.model") != usage.model
                or token_count(measured.properties.get("gen_ai.usage.input_tokens"))
                != usage.input_tokens
                or token_count(measured.properties.get("gen_ai.usage.output_tokens"))
                != usage.output_tokens
                or token_count(measured.properties.get("gen_ai.usage.cache_read.input_tokens"))
                != usage.cached_input_tokens
            ):
                problems.append("Exported usage differs from the provider response.")
    if not model_spans or priced != len(model_spans):
        problems.append("Required model-call price coverage is incomplete.")
    elapsed = max((run.end_utc - run.start_utc).total_seconds(), 0)
    latencies = sorted(request.elapsed_ms for request in run.requests)
    complete = not problems
    return {
        "variant": run.variant,
        "repetition": run.repetition,
        "revision": run.revision,
        "image": run.image,
        "conditionsHash": run.conditions_hash,
        "requestCount": len(run.requests),
        "successfulAnswers": successful,
        "expectedNonAnswers": sum(
            not request.failures
            and request.answer_status in {"unable-to-answer", "clarification-required"}
            for request in run.requests
        ),
        "qualityPercent": quality_passed * 100 / len(cases),
        "errorRatePercent": errors * 100 / max(len(run.requests), 1),
        "p95LatencyMs": latencies[math.ceil(len(latencies) * 0.95) - 1] if latencies else None,
        "throughputPerSecond": successful / elapsed if elapsed else None,
        "tokens": {
            direction: quantity if model_spans and direction not in unknown_quantities else None
            for direction, quantity in totals.items()
        },
        "knownTokenSubtotal": totals,
        "modelCalls": len(model_spans),
        "unpricedCalls": len(model_spans) - priced,
        "priceCoveragePercent": priced * 100 / len(model_spans) if model_spans else 0,
        "knownPricedSubtotalUsd": str(subtotal),
        "estimatedModelCostUsd": str(subtotal) if complete else None,
        "costPerSuccessfulAnswerUsd": (
            str(subtotal / successful) if complete and successful else None
        ),
        "costPer1000SuccessfulAnswersUsd": (
            str(subtotal / successful * 1000) if complete and successful else None
        ),
        "evidenceComplete": complete,
        "problems": sorted(set(problems)),
    }


def compare(
    definition: dict[str, object],
    runs: list[RunMeasurement],
    cases: list[GoldenCase],
    pricing: dict[str, object],
    *,
    questions_hash: str,
    conditions_hash: str,
    cleanup_succeeded: bool,
    agent_code_changed: bool,
    now: datetime,
) -> Comparison:
    rates, problems = price_rows(pricing, now)
    expected_revisions = validate_definition(definition)
    if len(cases) != 7 or len({case.id for case in cases}) != 7:
        raise ValueError("The exact seven unique golden cases are required.")
    if sorted((run.variant, run.repetition) for run in runs) != [
        ("baseline", 1),
        ("baseline", 2),
        ("candidate", 1),
    ]:
        problems.append("Two baselines and one candidate are required.")
    if len({run.experiment_id for run in runs}) != 1:
        problems.append("Runs belong to different experiments.")
    ordered = sorted(runs, key=lambda run: (run.variant, run.repetition))
    if any(
        left.end_utc > right.start_utc for left, right in zip(ordered, ordered[1:], strict=False)
    ):
        problems.append("The approved sequential measurement windows overlap.")
    all_spans = [span.span_id for run in runs for span in run.telemetry]
    all_sessions = [request.session_hash for run in runs for request in run.requests]
    if len(all_spans) != len(set(all_spans)) or len(all_sessions) != len(set(all_sessions)):
        problems.append("Consumption/session attribution is duplicated across runs.")
    if any(
        run.revision != expected_revisions[run.variant]
        or run.conditions_hash != conditions_hash
        or run.questions_hash != questions_hash
        or run.end_utc > now
        for run in runs
    ):
        problems.append("Revisions, conditions, questions, or times are not equivalent.")
    if not cleanup_succeeded:
        problems.append("Temporary experiment cleanup is not verified.")
    results = [analyze_run(run, cases, rates) for run in runs]
    complete = not problems and all(result["evidenceComplete"] for result in results)
    failed_guardrails = []
    for result in results:
        if result["qualityPercent"] != 100 or result["errorRatePercent"] != 0:
            failed_guardrails.append("Answer quality must be 100% and the error rate must be zero.")
    baseline = [result for result in results if result["variant"] == "baseline"]
    candidate = [result for result in results if result["variant"] == "candidate"]
    change = None
    spread = None
    decision = "repeat"
    if complete and len(baseline) == 2 and len(candidate) == 1:
        base_costs = [Decimal(str(result["costPerSuccessfulAnswerUsd"])) for result in baseline]
        mean = sum(base_costs, Decimal(0)) / Decimal(2)
        spread = (max(base_costs) - min(base_costs)) / mean * 100 if mean else None
        candidate_cost = Decimal(str(candidate[0]["costPerSuccessfulAnswerUsd"]))
        change = (candidate_cost - mean) / mean * 100 if mean else None
        baseline_latencies = [float(str(result["p95LatencyMs"])) for result in baseline]
        if float(str(candidate[0]["p95LatencyMs"])) > max(baseline_latencies) * 1.2:
            failed_guardrails.append("Candidate p95 latency regresses by more than 20%.")
        if failed_guardrails:
            decision = "reject"
        elif change is not None and change < 0 and spread is not None:
            decision = "accept" if -change > max(Decimal(5), spread) else "repeat"
        else:
            decision = "reject"
        if decision == "accept" and not agent_code_changed:
            decision = "repeat"
    return {
        "version": 1,
        "decision": decision,
        "evidenceComplete": complete,
        "cleanupSucceeded": cleanup_succeeded,
        "candidateChangeVerified": agent_code_changed,
        "costBasis": "Estimated public-retail model cost only, USD",
        "runs": results,
        "baselineCostSpreadPercent": str(spread) if spread is not None else None,
        "costChangePercent": str(change) if change is not None else None,
        "problems": sorted(set(problems)),
        "failedGuardrails": sorted(set(failed_guardrails)),
        "limitations": [
            "Small sequential fixed-question PoC, not a statistically powered benchmark.",
            "Shared model/provider conditions, cache state, and time-dependent latency can vary.",
            "Infrastructure, build, warm-up, telemetry, and shared charges are excluded.",
            "Build image digests remain in the shared registry as provenance artifacts.",
            "All measured calls, including failed/non-answer consumption, enter the numerator.",
            "Only correct, evaluated answered questions enter successful-answer denominators.",
            "A repeat/reject decision is not evidence of savings.",
            *(
                ["Unchanged agent logic: runner smoke test, not an optimization claim."]
                if not agent_code_changed
                else []
            ),
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--definition", required=True, type=Path)
    parser.add_argument("--runs", required=True, type=Path)
    parser.add_argument("--questions", required=True, type=Path)
    parser.add_argument("--pricing", required=True, type=Path)
    parser.add_argument("--conditions-hash", required=True)
    parser.add_argument("--cleanup", required=True, type=Path)
    parser.add_argument("--source-verification", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    questions_content = args.questions.read_bytes()
    definition = json.loads(args.definition.read_text())
    revisions = validate_definition(definition)
    verification = json.loads(args.source_verification.read_text())
    runs = [RunMeasurement.model_validate(value) for value in json.loads(args.runs.read_text())]
    cleanup = json.loads(args.cleanup.read_text())
    if (
        verification.get("baselineRevision") != revisions["baseline"]
        or verification.get("candidateRevision") != revisions["candidate"]
        or not isinstance(verification.get("agentCodeChanged"), bool)
        or not re.fullmatch(r"[a-f0-9]{64}", str(verification.get("protectedInputsHash")))
        or any(run.experiment_id != f"h09-{cleanup.get('runId')}" for run in runs)
    ):
        raise ValueError("Source verification or cleanup belongs to a different experiment.")
    result = compare(
        definition,
        runs,
        [GoldenCase.model_validate(value) for value in json.loads(questions_content)],
        json.loads(args.pricing.read_text()),
        questions_hash=hashlib.sha256(questions_content).hexdigest(),
        conditions_hash=args.conditions_hash,
        cleanup_succeeded=cleanup.get("verified") is True,
        agent_code_changed=verification["agentCodeChanged"],
        now=datetime.now(UTC),
    )
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    markdown = [
        "# Experiment decision",
        "",
        f"**Decision:** {result['decision']}",
        f"**Evidence complete:** {result['evidenceComplete']}",
        f"**Cleanup verified:** {result['cleanupSucceeded']}",
        f"**Eligible agent change:** {result['candidateChangeVerified']}",
        f"**Baseline cost spread (%):** {result['baselineCostSpreadPercent']}",
        f"**Candidate cost change (%):** {result['costChangePercent']} (negative means lower cost)",
        "**Basis:** Estimated public-retail USD model cost; see the retained pricing.json.",
        "",
        "| Variant | Pass | Revision | Answers | Model cost USD | Cost/answer USD | p95 ms |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for run in result["runs"]:
        markdown.append(
            f"| {run['variant']} | {run['repetition']} | {run['revision']} | "
            f"{run['successfulAnswers']} | {run['estimatedModelCostUsd']} | "
            f"{run['costPerSuccessfulAnswerUsd']} | {run['p95LatencyMs']} |"
        )
    markdown += [
        "",
        "| Variant | Pass | Quality % | Errors % | Priced calls % | USD/1,000 answers |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for run in result["runs"]:
        markdown.append(
            f"| {run['variant']} | {run['repetition']} | {run['qualityPercent']} | "
            f"{run['errorRatePercent']} | {run['priceCoveragePercent']} | "
            f"{run['costPer1000SuccessfulAnswersUsd']} |"
        )
    markdown += ["", "## Limitations", ""] + [f"- {value}" for value in result["limitations"]]
    markdown += ["", "## Blocking evidence", ""] + [f"- {value}" for value in result["problems"]]
    markdown += ["", "## Failed guardrails", ""] + [
        f"- {value}" for value in result["failedGuardrails"]
    ]
    args.output.with_suffix(".md").write_text("\n".join(markdown) + "\n")
    if not result["evidenceComplete"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
