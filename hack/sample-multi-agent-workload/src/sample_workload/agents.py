# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import asyncio
import logging
from uuid import uuid4

from pydantic import BaseModel, ValidationError

from .contracts import (
    Analysis,
    Answer,
    Classification,
    Evidence,
    QueryPlan,
    Question,
    SchemaContext,
)
from .database import SCHEMA, DatabaseUnavailable, QueryFailed, QueryRejected, Store
from .model import SCOPES, ModelClient, ModelDependencyError, summary

logger = logging.getLogger(__name__)


class JsonAgent[T: BaseModel]:
    def __init__(
        self,
        name: str,
        model: ModelClient,
        contract: type[T],
        timeout_seconds: float,
    ):
        self.name = name
        self.model = model
        self.contract = contract
        self.timeout_seconds = timeout_seconds

    async def run(self, context: dict[str, object], evidence: Evidence) -> T:
        if len(evidence.agent_calls) >= 4:
            raise ModelDependencyError("The agent call budget was exceeded.")
        evidence.agent_calls.append(self.name)
        response = await asyncio.wait_for(
            self.model.complete(self.name, context), timeout=self.timeout_seconds
        )
        return self.contract.model_validate_json(response)


class Coordinator:
    def __init__(self, store: Store, model: ModelClient, *, model_timeout_seconds: float = 5.0):
        if model_timeout_seconds <= 0:
            raise ValueError("The model timeout must be positive.")
        self.store = store
        self.model = model
        self.classifier = JsonAgent("coordinator", model, Classification, model_timeout_seconds)
        self.schema_agent = JsonAgent("schema-agent", model, SchemaContext, model_timeout_seconds)
        self.sql_agent = JsonAgent("sql-agent", model, QueryPlan, model_timeout_seconds)
        self.analysis_agent = JsonAgent("analysis-agent", model, Analysis, model_timeout_seconds)

    async def answer(self, question: Question) -> Answer:
        evidence = Evidence(model_mode=self.model.mode)
        result = Answer(
            request_id=f"req-{uuid4()}",
            answer_status="dependency-failed",
            answer="The request could not be completed.",
            evidence=evidence,
        )

        try:
            classification = await self.classifier.run({"question": question.question}, evidence)
            pattern = classification.pattern
            evidence.question_pattern = pattern
            if pattern == "shipment-delay-cause":
                result.answer_status = "unable-to-answer"
                result.answer = "Shipment delay causes are not recorded in the current schema."
                result.limitations = [
                    "Carrier milestone history, route events, and delay reasons are not modeled."
                ]
                return result
            if pattern == "unknown":
                result.answer_status = "clarification-required"
                result.answer = (
                    "Choose a supported retail question from the documented question set."
                )
                return result
            if pattern not in SCOPES:
                raise ModelDependencyError("The model returned an unknown question pattern.")
            schema = await self.schema_agent.run({"pattern": pattern, "schema": SCHEMA}, evidence)
            if set(schema.tables) != set(SCOPES[pattern]):
                raise ModelDependencyError("The model returned an unapproved schema scope.")
            plan = await self.sql_agent.run(
                {
                    "pattern": pattern,
                    "tables": schema.tables,
                    "question": question.question,
                    "referenceDate": evidence.reference_date,
                },
                evidence,
            )
            evidence.generated_sql = plan.sql
            data = await asyncio.to_thread(self.store.query, plan, frozenset(schema.tables))
            if pattern == "open-orders" and (
                data.columns != ["openOrders"]
                or len(data.rows) != 1
                or len(data.rows[0]) != 1
                or not isinstance(data.rows[0][0], int)
                or data.rows[0][0] < 0
            ):
                raise QueryFailed("The open-order result does not match its expected contract.")
            analysis = await self.analysis_agent.run(
                {"pattern": pattern, "data": data.model_dump()}, evidence
            )
            if analysis.answer != summary(pattern, data):
                raise QueryFailed("The analysis does not match the approved data-only summary.")
            result.answer_status = "answered"
            result.answer = analysis.answer
            result.data = data
            evidence.row_count = len(data.rows)
            return result
        except (ModelDependencyError, TimeoutError, ValidationError) as error:
            logger.error("Model dependency failed (%s).", type(error).__name__)
            result.answer_status = "dependency-failed"
            result.limitations = [
                "A model call failed, timed out, or returned an invalid contract."
            ]
        except QueryRejected:
            logger.warning("SQL validation rejected a generated query.")
            result.answer_status = "query-rejected"
            result.limitations = ["The generated query did not pass read-only scope validation."]
        except (QueryFailed, DatabaseUnavailable) as error:
            logger.error("Database or answer validation failed (%s).", type(error).__name__)
            result.answer_status = "query-failed"
            result.limitations = ["The query or data-only answer verification failed."]
        return result
