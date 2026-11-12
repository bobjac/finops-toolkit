# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import argparse
import asyncio
import hashlib
import json
from pathlib import Path
from types import TracebackType
from uuid import uuid4

import aiohttp
import pytest

from sample_workload import experiment_load
from sample_workload.contracts import Answer, Evidence, ModelUsage
from sample_workload.evaluation import GoldenCase
from sample_workload.experiment import RunMeasurement

QUESTIONS = Path(__file__).parent / "evaluation/questions.json"


class Response:
    status = 200

    def __init__(self, answer: Answer):
        self.answer = answer

    async def __aenter__(self) -> "Response":
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        pass

    async def json(self, *, content_type: str | None) -> object:
        return self.answer.model_dump(by_alias=True)


class Session:
    def __init__(self, clock: dict[str, float], *, fail: bool, latency: int):
        self.clock = clock
        self.fail = fail
        self.latency = latency
        self.starts: list[float] = []
        self.experiments: list[str] = []
        self.cases = {
            case.question: case
            for case in (
                GoldenCase.model_validate(value) for value in json.loads(QUESTIONS.read_text())
            )
        }

    async def __aenter__(self) -> "Session":
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        pass

    def post(
        self,
        url: str,
        *,
        headers: dict[str, str],
        json: dict[str, str],
        timeout: aiohttp.ClientTimeout,
        allow_redirects: bool,
    ) -> Response:
        assert url.startswith("https://ca-dto-x-123-b.")
        assert len(headers["x-sample-token"]) >= 32
        assert allow_redirects is False
        assert timeout.total is not None and 0 < timeout.total <= 230
        self.starts.append(self.clock["now"])
        self.experiments.append(json["experimentId"])
        self.clock["now"] += min(self.latency, timeout.total)
        if self.fail:
            raise aiohttp.ClientConnectionError("PRIVATE provider diagnostic")
        if self.latency > timeout.total:
            raise TimeoutError("PRIVATE timeout")
        case = self.cases[json["question"]]
        return Response(
            Answer(
                request_id=str(uuid4()),
                answer_status=case.expected_status,
                answer=case.expected_answer,
                data=case.expected_data,
                evidence=Evidence(
                    model_mode="azure-openai",
                    agent_calls=case.expected_calls,
                    row_count=len(case.expected_data.rows),
                    trace_id=uuid4().hex,
                    session_hash=hashlib.sha256(json["sessionId"].encode()).hexdigest(),
                    experiment_hash=hashlib.sha256(json["experimentId"].encode()).hexdigest(),
                    model_usage=[
                        ModelUsage(
                            model="gpt-5-mini",
                            input_tokens=100,
                            output_tokens=1,
                            cached_input_tokens=0,
                        )
                        for _ in case.expected_calls
                    ],
                ),
            )
        )


def arguments(path: Path, *, warmup: bool = False) -> argparse.Namespace:
    return argparse.Namespace(
        base_uri="https://ca-dto-x-123-b.synthetic.eastus2.azurecontainerapps.io",
        application_name="ca-dto-x-123-b",
        questions=QUESTIONS,
        experiment_id="h09-123",
        variant="baseline",
        repetition=1,
        revision="a" * 40,
        image="crftkdtohacksae46.azurecr.io/experiment@sha256:" + "f" * 64,
        conditions_hash="f" * 64,
        output=path,
        warmup=warmup,
    )


def fake_transport(
    monkeypatch: pytest.MonkeyPatch,
    *,
    fail: bool = False,
    latency: int = 0,
) -> Session:
    clock = {"now": 0.0}
    client = Session(clock, fail=fail, latency=latency)

    async def sleep(seconds: float) -> None:
        clock["now"] += seconds

    monkeypatch.setenv("SAMPLE_API_TOKEN", "synthetic-private-token-for-local-test")
    monkeypatch.setattr("sample_workload.experiment_load.time.monotonic", lambda: clock["now"])
    monkeypatch.setattr("sample_workload.experiment_load.asyncio.sleep", sleep)
    monkeypatch.setattr("sample_workload.experiment_load.aiohttp.ClientSession", lambda: client)
    return client


def test_fixed_schedule_is_sequential_paced_and_sanitized(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    client = fake_transport(monkeypatch)
    output = tmp_path / "run.json"
    asyncio.run(experiment_load.collect(arguments(output)))
    run = RunMeasurement.model_validate_json(output.read_text())
    assert client.starts == [0, 60, 120, 180, 240, 300, 360]
    assert len(run.requests) == 7
    assert len({request.session_hash for request in run.requests}) == 7
    assert sum(len(request.model_usage) for request in run.requests) == 22
    assert all(not request.failures for request in run.requests)
    assert "synthetic-private-token" not in output.read_text()
    assert "expectedAnswer" not in output.read_text()


def test_warmup_uses_one_request_and_a_separate_experiment_selection(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    client = fake_transport(monkeypatch)
    output = tmp_path / "warmup.json"
    asyncio.run(experiment_load.collect(arguments(output, warmup=True)))
    run = RunMeasurement.model_validate_json(output.read_text())
    assert client.starts == [0]
    assert client.clock["now"] == 60
    assert client.experiments == ["h09-123-warmup"]
    assert run.requests[0].case_id == "inventory-below-reorder"


def test_network_failures_are_measured_without_retries_or_private_diagnostics(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    client = fake_transport(monkeypatch, fail=True)
    output = tmp_path / "failure.json"
    asyncio.run(experiment_load.collect(arguments(output)))
    run = RunMeasurement.model_validate_json(output.read_text())
    assert len(client.starts) == 7
    assert all(request.http_status == 0 and request.failures for request in run.requests)
    assert "PRIVATE" not in output.read_text()


def test_ten_minute_deadline_preserves_partial_evidence_and_stops(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    client = fake_transport(monkeypatch, latency=230)
    output = tmp_path / "partial.json"
    with pytest.raises(RuntimeError, match="measurement window"):
        asyncio.run(experiment_load.collect(arguments(output)))
    assert client.clock["now"] == 600
    assert len(client.starts) == 3
    assert len(RunMeasurement.model_validate_json(output.read_text()).requests) == 3


@pytest.mark.parametrize(
    "endpoint",
    [
        "https://ca-dto-x-123-b.example.com",
        "https://ca-dto-x-123-b.synthetic.westeurope.azurecontainerapps.io",
        "https://ca-dto-x-123-b.synthetic.eastus2.azurecontainerapps.io/?redirect=elsewhere",
        "http://ca-dto-x-123-b.synthetic.eastus2.azurecontainerapps.io",
    ],
)
def test_invalid_endpoints_fail_before_transport(endpoint: str, tmp_path: Path) -> None:
    args = arguments(tmp_path / "invalid.json")
    args.base_uri = endpoint
    with pytest.raises(ValueError, match="HTTPS endpoint"):
        asyncio.run(experiment_load.collect(args))


def test_retained_app_cannot_be_selected_as_an_experiment(tmp_path: Path) -> None:
    args = arguments(tmp_path / "retained.json")
    args.application_name = "ca-ftk-dto-hack-s-ae46"
    args.base_uri = "https://ca-ftk-dto-hack-s-ae46.synthetic.eastus2.azurecontainerapps.io"
    with pytest.raises(ValueError, match="exact experiment"):
        asyncio.run(experiment_load.collect(args))
