# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

type Status = Literal[
    "answered",
    "clarification-required",
    "unable-to-answer",
    "query-rejected",
    "query-failed",
    "dependency-failed",
]
type Scalar = str | int | float | None


class Contract(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class Question(Contract):
    question: str = Field(min_length=1, max_length=1000, pattern=r"\S")
    session_id: str = Field(alias="sessionId", min_length=1, max_length=100)
    experiment_id: str = Field(alias="experimentId", min_length=1, max_length=100)
    variant: Literal["baseline", "candidate"] = "baseline"


class Classification(Contract):
    pattern: str


class SchemaContext(Contract):
    tables: list[str]


class QueryPlan(Contract):
    sql: str = Field(min_length=1, max_length=10000)
    parameters: dict[str, Scalar] = Field(default_factory=dict)


class Analysis(Contract):
    answer: str


class QueryData(Contract):
    columns: list[str] = Field(default_factory=list)
    rows: list[list[Scalar]] = Field(default_factory=list)


class Evidence(Contract):
    model_mode: str = Field(alias="modelMode")
    agent_calls: list[str] = Field(default_factory=list, alias="agentCalls")
    question_pattern: str | None = Field(default=None, alias="questionPattern")
    generated_sql: str | None = Field(default=None, alias="generatedSql")
    row_count: int = Field(default=0, alias="rowCount")
    schema_version: str = Field(default="1", alias="schemaVersion")
    reference_date: str = Field(default="2026-10-01", alias="referenceDate")


class Answer(Contract):
    request_id: str = Field(alias="requestId")
    answer_status: Status = Field(alias="answerStatus")
    answer: str
    data: QueryData = Field(default_factory=QueryData)
    evidence: Evidence
    limitations: list[str] = Field(default_factory=list)
