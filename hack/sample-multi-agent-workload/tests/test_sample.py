# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import asyncio
import json
import sqlite3
import subprocess
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from sample_workload.agents import Coordinator
from sample_workload.api import create_app
from sample_workload.contracts import Answer, QueryData, Question
from sample_workload.database import Store, initialize
from sample_workload.evaluation import GoldenCase, check, evaluate
from sample_workload.model import DeterministicModel, ModelDependencyError

GOLDEN = Path(__file__).parent / "evaluation/questions.json"
CASES = [GoldenCase.model_validate(value) for value in json.loads(GOLDEN.read_text())]


@pytest.fixture
def store(tmp_path: Path) -> Store:
    path = tmp_path / "retail.db"
    initialize(path)
    return Store(path)


@pytest.fixture
def client(store: Store) -> TestClient:
    return TestClient(create_app(Coordinator(store, DeterministicModel())))


def request(question: str) -> dict[str, str]:
    return {
        "question": question,
        "sessionId": "session-1",
        "experimentId": "experiment-1",
        "variant": "baseline",
    }


@pytest.mark.parametrize("case", CASES, ids=lambda case: case.id)
def test_golden_questions(client: TestClient, case: GoldenCase) -> None:
    response = client.post("/api/questions", json=request(case.question))
    assert response.status_code == 200
    result = Answer.model_validate(response.json())
    assert check(case, result) == []
    assert result.evidence.model_mode == "deterministic"
    assert result.request_id.startswith("req-")


def test_full_evaluation(store: Store) -> None:
    report = asyncio.run(evaluate(Coordinator(store, DeterministicModel()), GOLDEN))
    assert report["passed"] is True
    assert len(report["cases"]) == 7


def test_seed_is_reproducible_and_refuses_overwrite(tmp_path: Path) -> None:
    first, second = tmp_path / "first.db", tmp_path / "second.db"
    initialize(first, 42)
    initialize(second, 42)
    assert first.read_bytes() == second.read_bytes()
    with pytest.raises(FileExistsError):
        initialize(first, 43)
    third = tmp_path / "third.db"
    initialize(third, 43)
    assert first.read_bytes() != third.read_bytes()


class FailingModel(DeterministicModel):
    def __init__(self, role: str, response: str | None = None):
        self.role = role
        self.response = response

    async def complete(self, role: str, context: dict[str, object]) -> str:
        if role == self.role:
            if self.response is not None:
                return self.response
            raise ModelDependencyError("private-provider-diagnostic")
        return await super().complete(role, context)


@pytest.mark.parametrize("role", ["coordinator", "schema-agent", "sql-agent", "analysis-agent"])
def test_provider_failure_never_becomes_a_gap_or_fixture(
    store: Store,
    role: str,
    caplog: pytest.LogCaptureFixture,
) -> None:
    client = TestClient(create_app(Coordinator(store, FailingModel(role))))
    response = client.post("/api/questions", json=request(CASES[0].question))
    assert response.status_code == 503
    result = Answer.model_validate(response.json())
    assert result.answer_status == "dependency-failed"
    assert result.data.rows == []
    assert "private-provider-diagnostic" not in response.text + caplog.text


@pytest.mark.parametrize(
    ("role", "response", "status", "http_status"),
    [
        ("coordinator", "not-json", "dependency-failed", 503),
        ("coordinator", '{"pattern":"not-approved"}', "dependency-failed", 503),
        ("schema-agent", '{"tables":["sqlite_master"]}', "dependency-failed", 503),
        ("sql-agent", '{"sql":"DELETE FROM orders"}', "query-rejected", 422),
        ("sql-agent", '{"sql":"SELECT missing FROM orders"}', "query-failed", 500),
        ("sql-agent", '{"sql":"SELECT 1 AS unexpected"}', "query-failed", 500),
        ("analysis-agent", '{"answer":"Delays were caused by weather."}', "query-failed", 500),
    ],
)
def test_invalid_model_output_is_explicit(
    store: Store,
    role: str,
    response: str,
    status: str,
    http_status: int,
) -> None:
    client = TestClient(create_app(Coordinator(store, FailingModel(role, response))))
    question = CASES[2].question if "unexpected" in response else CASES[0].question
    result = client.post("/api/questions", json=request(question))
    assert result.status_code == http_status
    assert result.json()["answerStatus"] == status
    assert result.json()["data"]["rows"] == []


def test_model_timeout_does_not_fall_back(store: Store) -> None:
    class SlowModel(DeterministicModel):
        async def complete(self, role: str, context: dict[str, object]) -> str:
            await asyncio.sleep(10)
            return await super().complete(role, context)

    coordinator = Coordinator(store, SlowModel(), model_timeout_seconds=0.001)
    result = asyncio.run(coordinator.answer(Question.model_validate(request(CASES[0].question))))
    assert result.answer_status == "dependency-failed"
    assert result.evidence.agent_calls == ["coordinator"]


def test_readiness_without_azure_and_no_model_calls(client: TestClient) -> None:
    assert client.get("/health").status_code == 200
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.json()["modelMode"] == "deterministic"
    assert "not model or exporter access" in response.json()["limitations"][0]


@pytest.mark.parametrize("database_state", ["missing", "wrong-schema"])
def test_uninitialized_database_is_not_ready(tmp_path: Path, database_state: str) -> None:
    path = tmp_path / "uninitialized.db"
    if database_state == "wrong-schema":
        with sqlite3.connect(path) as connection:
            connection.execute("CREATE TABLE not_the_sample (id INTEGER)")
    client = TestClient(create_app(Coordinator(Store(path), DeterministicModel())))
    assert client.get("/ready").status_code == 503
    response = client.post("/api/questions", json=request(CASES[0].question))
    assert response.status_code == 500
    assert response.json()["answerStatus"] == "query-failed"
    assert database_state != "missing" or not path.exists()


@pytest.mark.parametrize("question", ["", "   ", "x" * 1001])
def test_invalid_question_is_rejected(client: TestClient, question: str) -> None:
    assert client.post("/api/questions", json=request(question)).status_code == 422


@pytest.mark.parametrize("change", ["invented-answer", "wrong-data", "extra-call", "gap-as-answer"])
def test_evaluator_detects_incorrect_results_and_invented_explanations(
    store: Store,
    change: str,
) -> None:
    case = CASES[5] if change == "gap-as-answer" else CASES[0]
    answer = asyncio.run(
        Coordinator(store, DeterministicModel()).answer(
            Question.model_validate(request(case.question))
        )
    )
    if change == "invented-answer":
        answer.answer = "Carrier delays were caused by weather."
    elif change == "wrong-data":
        answer.data = QueryData(columns=["category", "revenue"], rows=[["Water sports", 0]])
    elif change == "extra-call":
        answer.evidence.agent_calls.append("unnecessary-agent")
    else:
        answer.answer_status = "answered"
    assert check(case, answer)


def test_gap_has_no_sql_or_invented_cause(client: TestClient) -> None:
    result = client.post("/api/questions", json=request(CASES[5].question)).json()
    assert result["evidence"]["generatedSql"] is None
    assert result["evidence"]["agentCalls"] == ["coordinator"]
    assert result["limitations"]


@pytest.mark.parametrize("invalid_cases", ["wrong-result", "empty-set"])
def test_cli_failed_evaluation_writes_evidence_and_exits_nonzero(
    store: Store,
    tmp_path: Path,
    invalid_cases: str,
) -> None:
    values = json.loads(GOLDEN.read_text())
    if invalid_cases == "wrong-result":
        values[0]["expectedData"]["rows"][0][1] = 0
    else:
        values = []
    questions, output = tmp_path / "questions.json", tmp_path / "report.json"
    questions.write_text(json.dumps(values))
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "sample_workload",
            "evaluate",
            "--database",
            str(store.path),
            "--model-mode",
            "deterministic",
            "--questions",
            str(questions),
            "--output",
            str(output),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 1
    assert json.loads(output.read_text())["passed"] is False
