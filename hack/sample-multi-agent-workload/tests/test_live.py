# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import asyncio
import json
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient
from openai import AsyncAzureOpenAI
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter
from opentelemetry.trace import StatusCode

from sample_workload.agents import Coordinator
from sample_workload.api import create_app
from sample_workload.azure_model import AzureModel
from sample_workload.contracts import Question
from sample_workload.database import Store, initialize
from sample_workload.model import DeterministicModel


@pytest.mark.parametrize(
    "failure", [None, "uncached", "provider", "contract", "truncated", "empty"]
)
def test_live_sdk_usage_correlation_privacy_and_failure(
    tmp_path: Path,
    failure: str | None,
    caplog: pytest.LogCaptureFixture,
) -> None:
    async def exercise() -> None:
        calls: list[str] = []

        async def handler(request: httpx.Request) -> httpx.Response:
            assert request.headers["authorization"] == "Bearer test-identity-token"
            assert "api-key" not in request.headers
            payload = json.loads(request.content)
            role = next(
                name
                for name in ("coordinator", "schema-agent", "sql-agent", "analysis-agent")
                if f'"role": "{name}"' in payload["messages"][0]["content"]
            )
            calls.append(role)
            if failure == "provider" and role == "sql-agent":
                return httpx.Response(
                    429,
                    json={
                        "error": {
                            "message": "private-provider-prompt-secret",
                            "code": "rate_limit_exceeded",
                        }
                    },
                )
            content = await DeterministicModel().complete(
                role, json.loads(payload["messages"][1]["content"])
            )
            if failure == "contract" and role == "sql-agent":
                content = '{"private-database-row":"private-provider-prompt-secret"}'
            return httpx.Response(
                200,
                json={
                    "id": "chat-test",
                    "created": 1,
                    "object": "chat.completion",
                    "model": "gpt-5-mini-2025-08-07",
                    "choices": []
                    if failure == "empty"
                    else [
                        {
                            "index": 0,
                            "message": {"role": "assistant", "content": content},
                            "finish_reason": "length" if failure == "truncated" else "stop",
                        }
                    ],
                    "usage": {
                        "prompt_tokens": 100 + len(calls),
                        "completion_tokens": 10,
                        "total_tokens": 110 + len(calls),
                        "prompt_tokens_details": None
                        if failure == "uncached"
                        else {"cached_tokens": 50},
                    },
                },
            )

        async def identity_token() -> str:
            return "test-identity-token"

        sdk = AsyncAzureOpenAI(
            azure_endpoint="https://test.openai.azure.com",
            api_version="2024-10-21",
            azure_ad_token_provider=identity_token,
            max_retries=0,
            http_client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
        )
        exporter = InMemorySpanExporter()
        provider = TracerProvider()
        provider.add_span_processor(SimpleSpanProcessor(exporter))
        database = tmp_path / "retail.db"
        initialize(database)
        question = Question(
            question="Which products are below their reorder point?",
            session_id="private-session-secret",
            experiment_id="private-experiment-secret",
        )
        result = await Coordinator(
            Store(database),
            AzureModel(sdk, "gpt-5-mini"),
            model_timeout_seconds=45.0,
            tracer=provider.get_tracer("test"),
        ).answer(question)
        spans = exporter.get_finished_spans()
        model_spans = [span for span in spans if span.name == "gen_ai.chat"]
        assert len(calls) == len(model_spans)
        expected_usage_count = len(calls) - (1 if failure == "provider" else 0)
        assert len(result.evidence.model_usage) == expected_usage_count
        assert sum(usage.input_tokens for usage in result.evidence.model_usage) == sum(
            101 + index for index in range(expected_usage_count)
        )
        for index, usage in enumerate(result.evidence.model_usage):
            attributes = model_spans[index].attributes
            assert attributes is not None
            assert attributes["gen_ai.usage.input_tokens"] == usage.input_tokens == 101 + index
            assert attributes["gen_ai.usage.output_tokens"] == usage.output_tokens == 10
            if failure == "uncached":
                assert usage.cached_input_tokens is None
                assert "gen_ai.usage.cache_read.input_tokens" not in attributes
            else:
                assert (
                    attributes["gen_ai.usage.cache_read.input_tokens"]
                    == usage.cached_input_tokens
                    == 50
                )
        for span in spans:
            assert span.attributes is not None
            assert span.attributes["session.id"] == result.evidence.session_hash
            assert span.attributes["experiment.id"] == result.evidence.experiment_hash
            assert span.context is not None
            assert f"{span.context.trace_id:032x}" == result.evidence.trace_id
            assert not span.events
        serialized = str([(span.name, dict(span.attributes or {})) for span in spans])
        for private in (
            question.question,
            question.session_id,
            question.experiment_id,
            "private-provider-prompt-secret",
            "Lantern",
            "SELECT",
        ):
            assert private not in serialized
        assert "private-provider-prompt-secret" not in caplog.text
        if failure in {None, "uncached"}:
            assert result.answer_status == "answered"
            assert result.data.rows == [
                ["P-1002", "Lantern", 3, 5],
                ["P-1004", "Jacket", 2, 5],
            ]
            sql_span = next(span for span in spans if span.name == "sql-agent.run")
            db_span = next(span for span in spans if span.name == "db.query")
            assert sql_span.context is not None and db_span.parent is not None
            assert db_span.parent.span_id == sql_span.context.span_id
        else:
            assert result.answer_status == "dependency-failed"
            assert result.data.rows == []
            assert model_spans[-1].status.status_code == StatusCode.ERROR
        await sdk.close()
        provider.shutdown()

    asyncio.run(exercise())


def test_live_api_requires_token_before_model_calls(tmp_path: Path) -> None:
    class NeverCalled:
        mode = "azure-openai"

        async def complete(self, role: str, context: dict[str, object]) -> str:
            pytest.fail("An unauthorized request reached the model.")

    database = tmp_path / "retail.db"
    initialize(database)
    coordinator = Coordinator(Store(database), NeverCalled())
    with pytest.raises(ValueError, match="access token"):
        create_app(coordinator)
    client = TestClient(create_app(coordinator, api_token="a" * 32))
    response = client.post(
        "/api/questions",
        json={
            "question": "Which products are below their reorder point?",
            "sessionId": "test",
            "experimentId": "test",
        },
    )
    assert response.status_code == 401
    assert client.get("/ready").status_code == 200
    assert client.get("/ready").json()["modelMode"] == "azure-openai"
