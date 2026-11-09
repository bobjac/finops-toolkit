# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import asyncio
import logging
from uuid import uuid4

from opentelemetry.trace import SpanKind, StatusCode, Tracer
from opentelemetry.trace import Status as SpanStatus
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
from .model import SCOPES, ModelClient, ModelDependencyError, ModelResponse, summary
from .telemetry import correlation, default_tracer, safe_span

logger = logging.getLogger(__name__)


class JsonAgent[T: BaseModel]:
    def __init__(
        self,
        name: str,
        model: ModelClient,
        contract: type[T],
        timeout_seconds: float,
        tracer: Tracer,
    ):
        self.name = name
        self.model = model
        self.contract = contract
        self.timeout_seconds = timeout_seconds
        self.tracer = tracer

    async def run(
        self, context: dict[str, object], evidence: Evidence, attributes: dict[str, str]
    ) -> T:
        if len(evidence.agent_calls) >= 4:
            raise ModelDependencyError("The agent call budget was exceeded.")
        evidence.agent_calls.append(self.name)
        with safe_span(
            self.tracer,
            "gen_ai.chat",
            {
                **attributes,
                "agent.name": self.name,
                "gen_ai.provider.name": self.model.mode,
            },
            kind=SpanKind.CLIENT,
        ) as span:
            response = await asyncio.wait_for(
                self.model.complete(self.name, context), timeout=self.timeout_seconds
            )
            if isinstance(response, ModelResponse):
                usage = response.usage
                evidence.model_usage.append(usage)
                span.set_attribute("gen_ai.response.model", usage.model)
                span.set_attribute("gen_ai.usage.input_tokens", usage.input_tokens)
                span.set_attribute("gen_ai.usage.output_tokens", usage.output_tokens)
                if usage.cached_input_tokens is not None:
                    span.set_attribute(
                        "gen_ai.usage.cache_read.input_tokens", usage.cached_input_tokens
                    )
                if not response.complete:
                    raise ModelDependencyError("The model response is incomplete or refused.")
                content = response.content
            else:
                content = response
            return self.contract.model_validate_json(content)


class Coordinator:
    def __init__(
        self,
        store: Store,
        model: ModelClient,
        *,
        model_timeout_seconds: float = 5.0,
        tracer: Tracer | None = None,
    ):
        if model_timeout_seconds <= 0:
            raise ValueError("The model timeout must be positive.")
        self.store = store
        self.model = model
        self.tracer = tracer or default_tracer()
        self.classifier = JsonAgent(
            "coordinator", model, Classification, model_timeout_seconds, self.tracer
        )
        self.schema_agent = JsonAgent(
            "schema-agent", model, SchemaContext, model_timeout_seconds, self.tracer
        )
        self.sql_agent = JsonAgent(
            "sql-agent", model, QueryPlan, model_timeout_seconds, self.tracer
        )
        self.analysis_agent = JsonAgent(
            "analysis-agent", model, Analysis, model_timeout_seconds, self.tracer
        )

    async def answer(self, question: Question) -> Answer:
        attributes = correlation(question)
        with safe_span(self.tracer, "coordinator.run", attributes, kind=SpanKind.SERVER) as span:
            result = await self._answer(question, attributes)
            span.set_attribute("sample.answer_status", result.answer_status)
            if result.answer_status not in {
                "answered",
                "unable-to-answer",
                "clarification-required",
            }:
                span.set_status(SpanStatus(StatusCode.ERROR))
            trace_id = span.get_span_context().trace_id
            result.evidence.trace_id = f"{trace_id:032x}" if trace_id else None
            result.evidence.session_hash = attributes["session.id"]
            result.evidence.experiment_hash = attributes["experiment.id"]
            return result

    async def _answer(self, question: Question, attributes: dict[str, str]) -> Answer:
        evidence = Evidence(model_mode=self.model.mode)
        result = Answer(
            request_id=f"req-{uuid4()}",
            answer_status="dependency-failed",
            answer="The request could not be completed.",
            evidence=evidence,
        )

        try:
            classification = await self.classifier.run(
                {"question": question.question}, evidence, attributes
            )
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
            with safe_span(self.tracer, "schema-agent.run", attributes):
                schema = await self.schema_agent.run(
                    {"pattern": pattern, "schema": SCHEMA}, evidence, attributes
                )
            if set(schema.tables) != set(SCOPES[pattern]):
                raise ModelDependencyError("The model returned an unapproved schema scope.")
            with safe_span(self.tracer, "sql-agent.run", attributes):
                plan = await self.sql_agent.run(
                    {
                        "pattern": pattern,
                        "tables": schema.tables,
                        "schema": SCHEMA,
                        "question": question.question,
                        "referenceDate": evidence.reference_date,
                    },
                    evidence,
                    attributes,
                )
                evidence.generated_sql = plan.sql
                with safe_span(
                    self.tracer, "db.query", attributes, kind=SpanKind.CLIENT
                ) as db_span:
                    data = await asyncio.to_thread(self.store.query, plan, frozenset(schema.tables))
                    db_span.set_attribute("db.system.name", "sqlite")
                    db_span.set_attribute("db.response.returned_rows", len(data.rows))
            if pattern == "open-orders" and (
                data.columns != ["openOrders"]
                or len(data.rows) != 1
                or len(data.rows[0]) != 1
                or not isinstance(data.rows[0][0], int)
                or data.rows[0][0] < 0
            ):
                raise QueryFailed("The open-order result does not match its expected contract.")
            with safe_span(self.tracer, "analysis-agent.run", attributes):
                analysis = await self.analysis_agent.run(
                    {
                        "pattern": pattern,
                        "data": data.model_dump(),
                        "approvedAnswer": summary(pattern, data),
                    },
                    evidence,
                    attributes,
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
