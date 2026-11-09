# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import logging

from fastapi import FastAPI
from fastapi.responses import JSONResponse

from .agents import Coordinator
from .contracts import Question
from .database import DatabaseUnavailable

logger = logging.getLogger(__name__)


def create_app(coordinator: Coordinator) -> FastAPI:
    app = FastAPI(title="Contoso Outdoor offline retail sample")

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
                    "Live model access and telemetry exporter readiness are deferred to H05."
                ],
            }
        )

    @app.post("/api/questions")
    async def answer(question: Question) -> JSONResponse:
        result = await coordinator.answer(question)
        status = {
            "dependency-failed": 503,
            "query-rejected": 422,
            "query-failed": 500,
        }.get(result.answer_status, 200)
        return JSONResponse(result.model_dump(by_alias=True), status_code=status)

    return app
