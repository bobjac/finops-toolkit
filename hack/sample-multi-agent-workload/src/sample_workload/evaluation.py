# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import json
from pathlib import Path
from typing import TypedDict

from pydantic import Field

from .agents import Coordinator
from .contracts import Answer, Contract, QueryData, Question, Status


class GoldenCase(Contract):
    id: str
    question: str
    expected_status: Status = Field(alias="expectedStatus")
    expected_answer: str = Field(alias="expectedAnswer")
    expected_data: QueryData = Field(alias="expectedData")
    expected_calls: list[str] = Field(alias="expectedCalls")


class CaseResult(TypedDict):
    id: str
    passed: bool
    failures: list[str]


class EvaluationReport(TypedDict):
    modelMode: str
    referenceDate: str
    passed: bool
    cases: list[CaseResult]
    limitations: list[str]


def check(case: GoldenCase, answer: Answer) -> list[str]:
    failures = []
    if answer.answer_status != case.expected_status:
        failures.append("answerStatus")
    if answer.answer != case.expected_answer:
        failures.append("answer")
    if answer.data != case.expected_data:
        failures.append("data")
    if answer.evidence.agent_calls != case.expected_calls:
        failures.append("agentCalls")
    if answer.evidence.row_count != len(case.expected_data.rows):
        failures.append("rowCount")
    if case.expected_status != "answered" and answer.evidence.generated_sql is not None:
        failures.append("unexpectedSql")
    return failures


async def evaluate(coordinator: Coordinator, path: Path) -> EvaluationReport:
    cases = [GoldenCase.model_validate(value) for value in json.loads(path.read_text())]
    results: list[CaseResult] = []
    for case in cases:
        answer = await coordinator.answer(
            Question(
                question=case.question,
                session_id=f"golden-{case.id}",
                experiment_id="offline-evaluation",
            )
        )
        failures = check(case, answer)
        results.append({"id": case.id, "passed": not failures, "failures": failures})
    return {
        "modelMode": coordinator.model.mode,
        "referenceDate": "2026-10-01",
        "passed": bool(results) and all(result["passed"] for result in results),
        "cases": results,
        "limitations": [
            "Offline evaluation does not verify live models, tokens, prices, or savings."
        ],
    }
