# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import logging
from secrets import compare_digest

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from .agents import Coordinator
from .contracts import Question
from .database import DatabaseUnavailable

logger = logging.getLogger(__name__)


def create_app(coordinator: Coordinator, *, api_token: str | None = None) -> FastAPI:
    if coordinator.model.mode != "deterministic" and (api_token is None or len(api_token) < 32):
        raise ValueError("The live API requires an access token of at least 32 characters.")
    app = FastAPI(title="Contoso Outdoor retail sample")

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "healthy", "modelMode": coordinator.model.mode}

    @app.get("/ready")
    def ready() -> JSONResponse:
        try:
            coordinator.store.verify()
        except DatabaseUnavailable:
            logger.error("Readiness failed: the synthetic database is unavailable.")
            return JSONResponse({"status": "not-ready"}, status_code=503)
        return JSONResponse(
            {
                "status": "ready",
                "modelMode": coordinator.model.mode,
                "limitations": [
                    "Readiness checks local configuration, not model or exporter access."
                ],
            }
        )

    @app.post("/api/questions")
    async def answer(question: Question, request: Request) -> JSONResponse:
        if api_token is not None and not compare_digest(
            request.headers.get("x-sample-token", "").encode(), api_token.encode()
        ):
            return JSONResponse({"error": "Unauthorized."}, status_code=401)
        result = await coordinator.answer(question)
        status = {
            "dependency-failed": 503,
            "query-rejected": 422,
            "query-failed": 500,
        }.get(result.answer_status, 200)
        return JSONResponse(result.model_dump(by_alias=True), status_code=status)

    return app
