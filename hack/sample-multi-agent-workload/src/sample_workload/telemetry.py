# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

from collections.abc import Iterator
from contextlib import contextmanager
from hashlib import sha256

from opentelemetry import trace
from opentelemetry.trace import Span, SpanKind, Status, StatusCode, Tracer

from .contracts import Question


def correlation(question: Question) -> dict[str, str]:
    return {
        "experiment.id": sha256(question.experiment_id.encode()).hexdigest(),
        "session.id": sha256(question.session_id.encode()).hexdigest(),
        "optimization.variant": question.variant,
    }


@contextmanager
def safe_span(
    tracer: Tracer,
    name: str,
    attributes: dict[str, str],
    *,
    kind: SpanKind = SpanKind.INTERNAL,
) -> Iterator[Span]:
    # SDK exception events include exception messages and stack traces; never export them.
    with tracer.start_as_current_span(
        name,
        attributes=attributes,
        kind=kind,
        record_exception=False,
        set_status_on_exception=False,
    ) as span:
        try:
            yield span
        except Exception:
            span.set_status(Status(StatusCode.ERROR))
            raise


def default_tracer() -> Tracer:
    return trace.get_tracer("sample_workload")
