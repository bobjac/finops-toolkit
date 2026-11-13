# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import hashlib
import json
import sys
from copy import deepcopy
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import pytest

from sample_workload.contracts import Answer, Evidence, ModelUsage
from sample_workload.evaluation import GoldenCase
from sample_workload.experiment import (
    RunMeasurement,
    analyze_run,
    compare,
    main,
    price_rows,
    validate_definition,
)
from sample_workload.experiment_load import record_response
from sample_workload.experiment_sources import PROTECTED, validate_sources

ROOT = Path(__file__).parents[1]
NOW = datetime(2026, 11, 12, 12, tzinfo=UTC)
HASH = "f" * 64
BASELINE = "a" * 40
CANDIDATE = "b" * 40
CASES = [
    GoldenCase.model_validate(value)
    for value in json.loads((ROOT / "tests/evaluation/questions.json").read_text())
]


def definition() -> dict[str, Any]:
    result: dict[str, Any] = json.loads(
        (ROOT / "experiments/schema-context.experiment.json").read_text()
    )
    result["variants"]["baseline"]["ref"] = BASELINE
    result["variants"]["candidate"]["ref"] = CANDIDATE
    return result


def pricing() -> dict[str, Any]:
    return {
        "tool": "get_current_pricing",
        "source": "finops-hub",
        "dataScope": {
            "model": "gpt-5-mini",
            "region": "eastus2",
            "currency": "USD",
            "deploymentSku": "GlobalStandard",
        },
        "freshness": {"pricingAsOf": (NOW - timedelta(days=1)).isoformat()},
        "evidence": [{"sourceUrl": "https://prices.azure.com/api/retail/prices"}],
        "data": {
            "rows": [
                {
                    "Direction": direction,
                    "Price": rate,
                    "MeterId": f"meter-{direction}",
                    "Unit": "1M",
                    "BlockSize": 1_000_000,
                    "Currency": "USD",
                    "Region": "US East 2",
                    "Offer": "PUBLIC-RETAIL",
                    "EffectiveStart": "2025-08-01T00:00:00Z",
                    "EffectiveEnd": None,
                }
                for direction, rate in (("input", "1"), ("cachedInput", "0.1"), ("output", "2"))
            ]
        },
    }


def measured(variant: str, repetition: int, tokens: int = 1000) -> RunMeasurement:
    start = NOW - timedelta(minutes=45 - repetition * 12 - (24 if variant == "candidate" else 0))
    requests = []
    spans = []
    experiment_hash = hashlib.sha256(b"h09-123").hexdigest()
    for index, case in enumerate(CASES):
        prefix = f"{variant}-{repetition}-{index}"
        session_hash = hashlib.sha256(prefix.encode()).hexdigest()
        trace = hashlib.md5(prefix.encode(), usedforsecurity=False).hexdigest()
        properties: dict[str, object] = {
            "experiment.id": experiment_hash,
            "optimization.variant": variant,
        }
        common = {
            "AppVersion": BASELINE if variant == "baseline" else CANDIDATE,
            "TimeGenerated": (start + timedelta(seconds=index * 60)).isoformat(),
            "OperationId": trace,
            "SessionId": session_hash,
        }
        spans.append(
            {
                **common,
                "Name": "coordinator.run",
                "Id": prefix,
                "ParentId": None,
                "Properties": properties,
            }
        )
        usage = []
        for role in case.expected_calls:
            usage.append(
                {
                    "model": "gpt-5-mini-2025-08-07",
                    "inputTokens": tokens,
                    "cachedInputTokens": tokens // 2,
                    "outputTokens": tokens // 10,
                }
            )
            spans.append(
                {
                    **common,
                    "Name": "gen_ai.chat",
                    "Id": f"{prefix}-{role}",
                    "ParentId": prefix,
                    "Properties": {
                        **properties,
                        "agent.name": role,
                        "gen_ai.response.model": "gpt-5-mini-2025-08-07",
                        "gen_ai.usage.input_tokens": tokens,
                        "gen_ai.usage.cache_read.input_tokens": tokens // 2,
                        "gen_ai.usage.output_tokens": tokens // 10,
                    },
                }
            )
        requests.append(
            {
                "caseId": case.id,
                "sessionHash": session_hash,
                "elapsedMs": 1000,
                "httpStatus": 200,
                "answerStatus": case.expected_status,
                "traceId": trace,
                "failures": [],
                "agentCalls": case.expected_calls,
                "modelUsage": usage,
            }
        )
    return RunMeasurement.model_validate(
        {
            "experimentId": "h09-123",
            "variant": variant,
            "repetition": repetition,
            "revision": BASELINE if variant == "baseline" else CANDIDATE,
            "image": "crftkdtohacksae46.azurecr.io/experiment@sha256:" + HASH,
            "conditionsHash": HASH,
            "questionsHash": HASH,
            "startUtc": start.isoformat(),
            "endUtc": (start + timedelta(minutes=7)).isoformat(),
            "requests": requests,
            "telemetry": spans,
        }
    )


def decision(
    runs: list[RunMeasurement] | None = None,
    prices: dict[str, Any] | None = None,
    *,
    cleanup: bool = True,
) -> dict[str, Any]:
    return dict(
        compare(
            definition(),
            runs
            if runs is not None
            else [
                measured("baseline", 1),
                measured("baseline", 2),
                measured("candidate", 1, 800),
            ],
            CASES,
            prices if prices is not None else pricing(),
            questions_hash=HASH,
            conditions_hash=HASH,
            cleanup_succeeded=cleanup,
            agent_code_changed=True,
            now=NOW,
        )
    )


def test_cached_tokens_and_nonanswers_are_priced_once() -> None:
    rates, errors = price_rows(pricing(), NOW)
    assert not errors
    result = analyze_run(measured("baseline", 1), CASES, rates)
    # Each call: 500 uncached + 500 cached + 100 output tokens = USD 0.00075.
    assert Decimal(str(result["estimatedModelCostUsd"])) == Decimal("0.01650")
    assert result["modelCalls"] == 22
    assert result["successfulAnswers"] == 5
    assert result["expectedNonAnswers"] == 2
    assert Decimal(str(result["costPerSuccessfulAnswerUsd"])) == Decimal("0.00330")
    assert Decimal(str(result["costPer1000SuccessfulAnswersUsd"])) == Decimal("3.30")
    assert result["priceCoveragePercent"] == 100


@pytest.mark.parametrize(
    "session_shape",
    [
        "promoted",
        "matching-duplicate",
        "conflicting-duplicate",
        "null-duplicate",
        "unknown-session",
    ],
)
def test_exported_session_attribution_preserves_strict_correlation(session_shape: str) -> None:
    runs = [measured("baseline", 1), measured("baseline", 2), measured("candidate", 1, 800)]
    if session_shape == "matching-duplicate":
        for run in runs:
            for span in run.telemetry:
                span.properties["session.id"] = span.session_hash
    elif session_shape == "conflicting-duplicate":
        runs[2].telemetry[0].properties["session.id"] = "0" * 64
    elif session_shape == "null-duplicate":
        runs[2].telemetry[0].properties["session.id"] = None
    elif session_shape == "unknown-session":
        runs[2].telemetry[0].session_hash = "0" * 64
    result = decision(runs)
    complete = session_shape in {"promoted", "matching-duplicate"}
    assert result["evidenceComplete"] is complete
    assert result["decision"] == ("accept" if complete else "repeat")
    if not complete:
        assert result["runs"][2]["estimatedModelCostUsd"] is None
        assert any("candidate pass 1:" in problem for problem in result["problems"])


def test_failed_consumption_remains_in_numerator_and_rejects() -> None:
    runs = [measured("baseline", 1), measured("baseline", 2), measured("candidate", 1)]
    request = runs[2].requests[0]
    request.http_status = 500
    request.answer_status = "query-failed"
    request.failures = ["answerStatus", "http-status"]
    result = decision(runs)
    assert result["evidenceComplete"] is True
    assert result["decision"] == "reject"
    candidate = result["runs"][2]
    assert Decimal(candidate["estimatedModelCostUsd"]) == Decimal("0.01650")
    assert candidate["successfulAnswers"] == 4
    assert Decimal(candidate["costPerSuccessfulAnswerUsd"]) == Decimal("0.004125")


def test_zero_successful_answers_is_unknown_not_free() -> None:
    run = measured("candidate", 1)
    for request in run.requests:
        request.failures = ["answer"]
    result = decision([measured("baseline", 1), measured("baseline", 2), run])
    assert result["decision"] == "repeat"
    assert result["runs"][2]["costPerSuccessfulAnswerUsd"] is None


@pytest.mark.parametrize(
    "failure",
    [
        "currency",
        "missing",
        "stale",
        "future",
        "expired",
        "duplicate-meter",
        "units",
        "negative",
        "region",
    ],
)
def test_invalid_prices_cannot_authorize_savings(failure: str) -> None:
    prices = pricing()
    row = prices["data"]["rows"][0]
    if failure == "currency":
        row["Currency"] = "EUR"
    elif failure == "missing":
        prices["data"]["rows"].pop()
    elif failure in {"stale", "future"}:
        prices["freshness"]["pricingAsOf"] = (
            NOW + timedelta(days=1 if failure == "future" else -8)
        ).isoformat()
    elif failure == "expired":
        row["EffectiveEnd"] = (NOW - timedelta(hours=1)).isoformat()
    elif failure == "duplicate-meter":
        row["MeterId"] = prices["data"]["rows"][1]["MeterId"]
    elif failure == "units":
        row["BlockSize"] = 1000
    elif failure == "region":
        row["Region"] = "West US"
    else:
        row["Price"] = -1
    result = decision(prices=prices)
    assert result["decision"] == "repeat"
    assert result["evidenceComplete"] is False
    assert result["runs"][2]["estimatedModelCostUsd"] is None


@pytest.mark.parametrize(
    "failure",
    [
        "unknown-cache",
        "wrong-model",
        "duplicate-span",
        "missing-span",
        "wrong-revision",
        "wrong-parent",
        "wrong-experiment",
        "wrong-session",
        "duplicate-session",
        "provider-mismatch",
        "questions",
        "conditions",
        "outside-window",
        "duplicate-pass",
    ],
)
def test_incomplete_or_duplicate_attribution_blocks_acceptance(failure: str) -> None:
    runs = [measured("baseline", 1), measured("baseline", 2), measured("candidate", 1, 800)]
    run = runs[2]
    span = run.telemetry[1]
    if failure == "unknown-cache":
        del span.properties["gen_ai.usage.cache_read.input_tokens"]
    elif failure == "wrong-model":
        span.properties["gen_ai.response.model"] = "unpriced-model"
    elif failure == "duplicate-span":
        run.telemetry.append(span.model_copy(deep=True))
    elif failure == "missing-span":
        run.telemetry.pop(1)
    elif failure == "wrong-revision":
        span.revision = BASELINE
    elif failure == "wrong-parent":
        span.parent_id = run.telemetry[-1].span_id
    elif failure == "wrong-experiment":
        span.properties["experiment.id"] = "0" * 64
    elif failure == "wrong-session":
        span.session_hash = "0" * 64
    elif failure == "duplicate-session":
        run.requests[0].session_hash = run.requests[1].session_hash
    elif failure == "provider-mismatch":
        run.requests[0].model_usage[0].input_tokens += 1
    elif failure == "questions":
        run.questions_hash = "0" * 64
    elif failure == "conditions":
        run.conditions_hash = "0" * 64
    elif failure == "outside-window":
        span.timestamp = NOW
    else:
        runs[1] = runs[0].model_copy(deep=True)
    result = decision(runs)
    assert result["evidenceComplete"] is False
    assert result["decision"] != "accept"
    if failure == "unknown-cache":
        assert result["runs"][2]["tokens"]["cachedInput"] is None
        assert result["runs"][2]["tokens"]["input"] == 17600


@pytest.mark.parametrize(
    ("baseline2", "candidate", "expected"),
    [
        (1000, 800, "accept"),
        (1000, 950, "repeat"),
        (1000, 1000, "reject"),
        (1200, 1000, "repeat"),
        (1200, 800, "accept"),
    ],
)
def test_improvement_must_exceed_five_percent_and_baseline_variation(
    baseline2: int,
    candidate: int,
    expected: str,
) -> None:
    result = decision(
        [
            measured("baseline", 1),
            measured("baseline", 2, baseline2),
            measured("candidate", 1, candidate),
        ]
    )
    assert result["evidenceComplete"] is True
    assert result["decision"] == expected


def test_latency_and_cleanup_are_hard_gates() -> None:
    runs = [measured("baseline", 1), measured("baseline", 2), measured("candidate", 1, 800)]
    runs[2].requests[0].elapsed_ms = 1201
    assert decision(runs)["decision"] == "reject"
    assert decision(cleanup=False)["decision"] == "repeat"


def test_unchanged_agent_smoke_cannot_claim_optimization_savings() -> None:
    result = compare(
        definition(),
        [measured("baseline", 1), measured("baseline", 2), measured("candidate", 1, 800)],
        CASES,
        pricing(),
        questions_hash=HASH,
        conditions_hash=HASH,
        cleanup_succeeded=True,
        agent_code_changed=False,
        now=NOW,
    )
    assert result["evidenceComplete"] is True
    assert result["decision"] == "repeat"
    assert result["candidateChangeVerified"] is False


def test_extra_or_weakened_guardrails_are_not_ignored() -> None:
    spec = definition()
    spec["guardrails"]["ignored"] = {"maximum": 0}
    with pytest.raises(ValueError, match="guardrails"):
        validate_definition(spec)
    spec = definition()
    spec["guardrails"]["answerQualityPercent"]["minimum"] = 90
    with pytest.raises(ValueError):
        validate_definition(spec)


def test_response_measurements_preserve_failure_usage_without_raw_content() -> None:
    case = CASES[0]
    usage = ModelUsage(model="gpt-5-mini", input_tokens=100, output_tokens=1)
    answer = Answer(
        request_id="synthetic",
        answer_status="dependency-failed",
        answer="PRIVATE RESPONSE",
        evidence=Evidence(
            model_mode="azure-openai",
            agent_calls=["coordinator"],
            model_usage=[usage],
            session_hash=HASH,
            experiment_hash=HASH,
            trace_id="a" * 32,
            generated_sql="PRIVATE SQL",
        ),
    )
    result = record_response(
        case,
        answer.model_dump(by_alias=True),
        http_status=503,
        session_hash=HASH,
        experiment_hash=HASH,
        elapsed_ms=120,
    )
    assert result.model_usage == [usage]
    assert "http-status" in result.failures
    assert "PRIVATE" not in result.model_dump_json()
    invalid = record_response(
        case,
        {"token": "PRIVATE"},
        http_status=200,
        session_hash=HASH,
        experiment_hash=HASH,
        elapsed_ms=0,
    )
    assert invalid.failures == ["response-contract"]


def test_candidate_cannot_change_runtime_accounting_or_data() -> None:
    baseline = {
        path: (ROOT / path).read_bytes() for path in (*PROTECTED, "src/sample_workload/agents.py")
    }
    candidate = deepcopy(baseline)
    candidate["src/sample_workload/agents.py"] = candidate["src/sample_workload/agents.py"].replace(
        b">= 4:",
        b">= 400:",
    )
    with pytest.raises(ValueError, match="measurement"):
        validate_sources(baseline, candidate)
    candidate = deepcopy(baseline)
    candidate["src/sample_workload/database.py"] += b"\n# changed data rules"
    with pytest.raises(ValueError, match="protected input"):
        validate_sources(baseline, candidate)
    assert validate_sources(baseline, baseline)["agentCodeChanged"] is False
    candidate = deepcopy(baseline)
    candidate["src/sample_workload/agents.py"] += b"\n# Documentation-only change.\n"
    assert validate_sources(baseline, candidate)["agentCodeChanged"] is False
    # Keep an unoptimized prompt fixture even after the checkout contains the candidate.
    baseline["src/sample_workload/agents.py"] = (
        b'def prompt(pattern):\n    return {"schema": SCHEMA}\n'
    )
    candidate = deepcopy(baseline)
    expression = (
        b"';'.join(statement for statement in SCHEMA.split(';') "
        b"if any(statement.lstrip().startswith(f'CREATE TABLE {table}(') "
        b"for table in SCOPES[pattern])) + ';'"
    )
    candidate["src/sample_workload/agents.py"] = baseline["src/sample_workload/agents.py"].replace(
        b'"schema": SCHEMA', b'"schema": ' + expression
    )
    assert validate_sources(baseline, candidate)["agentCodeChanged"] is True


@pytest.mark.parametrize("complete", [True, False])
def test_offline_cli_writes_both_reports_and_signals_incomplete_evidence(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    complete: bool,
) -> None:
    questions = ROOT / "tests/evaluation/questions.json"
    questions_hash = hashlib.sha256(questions.read_bytes()).hexdigest()
    runs = [measured("baseline", 1), measured("baseline", 2), measured("candidate", 1, 800)]
    for run in runs:
        run.questions_hash = questions_hash
    prices = pricing()
    if not complete:
        prices["data"]["rows"].pop()
    files = {
        "definition": definition(),
        "runs": [run.model_dump(mode="json", by_alias=True) for run in runs],
        "pricing": prices,
        "cleanup": {"verified": True, "runId": "123"},
        "source-verification": {
            "baselineRevision": BASELINE,
            "candidateRevision": CANDIDATE,
            "protectedInputsHash": HASH,
            "agentCodeChanged": True,
        },
    }
    arguments = ["experiment", "--questions", str(questions), "--conditions-hash", HASH]
    for name, value in files.items():
        path = tmp_path / f"{name}.json"
        path.write_text(json.dumps(value))
        arguments += [f"--{name}", str(path)]
    output = tmp_path / "decision.json"
    arguments += ["--output", str(output)]
    monkeypatch.setattr(sys, "argv", arguments)
    monkeypatch.setattr(
        "sample_workload.experiment.datetime",
        SimpleNamespace(now=lambda zone: NOW, fromisoformat=datetime.fromisoformat),
    )
    if complete:
        main()
    else:
        with pytest.raises(SystemExit) as error:
            main()
        assert error.value.code == 2
    result = json.loads(output.read_text())
    assert result["evidenceComplete"] is complete
    assert result["decision"] == ("accept" if complete else "repeat")
    markdown = output.with_suffix(".md").read_text()
    assert BASELINE in markdown and CANDIDATE in markdown
    assert "Quality %" in markdown and "Priced calls %" in markdown
