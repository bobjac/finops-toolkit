# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import os
import re
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

import uvicorn
from azure.identity import ManagedIdentityCredential
from azure.identity.aio import ManagedIdentityCredential as AsyncManagedIdentityCredential
from azure.identity.aio import get_bearer_token_provider
from azure.monitor.opentelemetry.exporter import AzureMonitorTraceExporter
from fastapi import FastAPI
from openai import AsyncAzureOpenAI
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

from .agents import Coordinator
from .api import create_app
from .azure_model import AzureModel
from .database import Store
from .model import DeterministicModel


def required(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        raise ValueError(f"Required runtime setting is missing: {name}.")
    return value


def application() -> FastAPI:
    mode = required("SAMPLE_MODEL_MODE")
    store = Store(Path(required("SAMPLE_DATABASE")))
    store.verify()
    if mode == "deterministic":
        return create_app(Coordinator(store, DeterministicModel()))
    if mode != "azure-openai":
        raise ValueError("The configured model mode is unsupported.")
    token = required("SAMPLE_API_TOKEN")
    if len(token) < 32:
        raise ValueError("The live API access token is too short.")
    endpoint = required("AZURE_OPENAI_ENDPOINT")
    if not re.fullmatch(r"https://[a-z0-9-]+\.openai\.azure\.com/?", endpoint):
        raise ValueError("The model endpoint must be an Azure OpenAI HTTPS endpoint.")
    client_id = required("AZURE_CLIENT_ID")
    deployment = required("AZURE_OPENAI_DEPLOYMENT")
    api_version = required("AZURE_OPENAI_API_VERSION")
    connection_string = required("APPLICATIONINSIGHTS_CONNECTION_STRING")
    credential = AsyncManagedIdentityCredential(client_id=client_id)
    export_credential = ManagedIdentityCredential(client_id=client_id)
    client = AsyncAzureOpenAI(
        azure_endpoint=endpoint,
        azure_ad_token_provider=get_bearer_token_provider(
            credential, "https://cognitiveservices.azure.com/.default"
        ),
        api_version=api_version,
        max_retries=0,
        timeout=40.0,
    )
    provider = TracerProvider(
        resource=Resource.create(
            {
                "service.name": "contoso-outdoor-agent",
                "service.version": os.environ.get("SAMPLE_REVISION", "unknown"),
            }
        )
    )
    provider.add_span_processor(
        BatchSpanProcessor(
            AzureMonitorTraceExporter(
                connection_string=connection_string,
                credential=export_credential,
                disable_offline_storage=True,
            )
        )
    )
    model = AzureModel(client, deployment)
    app = create_app(
        Coordinator(
            store,
            model,
            model_timeout_seconds=45.0,
            tracer=provider.get_tracer("sample_workload"),
        ),
        api_token=token,
    )

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        try:
            yield
        finally:
            await client.close()
            await credential.close()
            provider.shutdown()
            export_credential.close()

    app.router.lifespan_context = lifespan
    return app


def main() -> None:
    uvicorn.run(application(), host="0.0.0.0", port=8080, access_log=False)


if __name__ == "__main__":
    main()
