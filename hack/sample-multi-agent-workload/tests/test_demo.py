# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import base64
import hashlib
import json
import webbrowser
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

import pytest
from test_experiment import CASES, NOW, definition, measured, pricing

from sample_workload import demo
from sample_workload.contracts import Answer, Evidence
from sample_workload.experiment import compare

ROOT = Path(__file__).parents[1]
QUESTIONS = ROOT / "tests/evaluation/questions.json"


def save(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    demo.write(path, value)


def inputs(path: Path) -> Path:
    root = path / "private"
    verification = {
        "baselineRevision": "a" * 40,
        "candidateRevision": "b" * 40,
        "agentCodeChanged": True,
        "protectedInputsHash": "e" * 64,
        "protectedInputs": {"tests/evaluation/questions.json": demo.digest(QUESTIONS)},
    }
    verification["protectedInputsHash"] = hashlib.sha256(
        json.dumps(verification["protectedInputs"], sort_keys=True).encode()
    ).hexdigest()
    conditions = {
        "source": verification,
        "runtime": {
            "model": "gpt-5-mini",
            "modelVersion": "2025-08-07",
            "sku": "GlobalStandard",
            "seed": 42,
            "replicas": 1,
            "cpu": 0.25,
            "memory": "0.5Gi",
        },
        "policy": {
            key: definition()[key]
            for key in ("adapter", "workloadUnit", "scope", "load", "guardrails", "cost", "cleanup")
        },
        "controller": {
            name: demo.digest(ROOT / name).upper()
            for name in (
                "src/sample_workload/experiment.py",
                "src/sample_workload/experiment_sources.py",
            )
        },
    }
    save(root / "experiment/conditions.json", conditions)
    conditions_hash = demo.digest(root / "experiment/conditions.json")
    (root / "experiment/conditions.sha256").write_text(conditions_hash)
    save(root / "experiment/definition.json", definition())
    save(root / "experiment/source-verification.json", verification)
    runs = [measured("baseline", 1), measured("baseline", 2), measured("candidate", 1, 800)]
    runs = [
        run.model_copy(
            update={
                "conditions_hash": conditions_hash,
                "questions_hash": demo.digest(QUESTIONS),
            }
        )
        for run in runs
    ]
    save(
        root / "experiment/runs.json", [run.model_dump(mode="json", by_alias=True) for run in runs]
    )
    save(root / "experiment/pricing.json", pricing())
    save(root / "experiment/seed-run.json", {"id": 900})
    save(
        root / "experiment/cleanup.json",
        {
            "runId": "123",
            "verified": True,
            "failures": [],
            "completedUtc": NOW.isoformat(),
        },
    )
    result = compare(
        definition(),
        runs,
        CASES,
        pricing(),
        questions_hash=demo.digest(QUESTIONS),
        conditions_hash=conditions_hash,
        cleanup_succeeded=True,
        agent_code_changed=True,
        now=NOW,
    )
    save(root / "experiment/decision.json", result)
    for kind, run_id, workflow in (
        ("experiment", 123, "sample-experiment"),
        ("deployment", 456, "sandbox-deploy"),
        ("context", 789, "sandbox-context"),
    ):
        save(
            root / f"{kind}-run.json",
            {
                "id": run_id,
                "run_attempt": 1,
                "head_sha": "c" * 40,
                "repository": {"full_name": demo.REPOSITORY},
                "head_branch": "dev",
                "event": "workflow_dispatch",
                "path": f".github/workflows/{workflow}.yml",
                "status": "completed",
                "conclusion": "success",
                "created_at": (NOW - timedelta(hours=1)).isoformat(),
                "updated_at": (
                    NOW - timedelta(minutes=45) if kind == "context" else NOW
                ).isoformat(),
                "actor": {"email": "never-export-this"},
            },
        )
    application = "https://ca-ftk-dto-hack-s-ae46.synthetic.eastus2.azurecontainerapps.io"
    save(
        root / "deployment/readiness.json",
        {
            "ready": True,
            "status": "VerifiedAndRetained",
            "runId": "456",
            "runAttempt": "1",
            "revision": "c" * 40,
            "links": {
                "application": application,
                "workbook": f"https://portal.azure.com/#@/resource{demo.SCOPE}"
                "/providers/Microsoft.Insights/workbooks/"
                "478410d0-a0ae-5679-89fe-eea6a576654c/workbook",
            },
        },
    )
    save(
        root / "sample/deployment-validation.json",
        {
            "revision": "c" * 40,
            "runId": "456",
            "runAttempt": "1",
            "liveVerified": True,
            "subscriptionId": demo.SUBSCRIPTION,
            "resourceGroup": "ftk-dto-hack-s-ae46",
            "expiresOn": (NOW + timedelta(days=30)).isoformat(),
            "outputs": {"fqdn": {"value": application.removeprefix("https://")}},
        },
    )
    experiment_hash = hashlib.sha256(b"h09-123").hexdigest()
    save(
        root / "viewer.json",
        {
            "checkedUtc": NOW.isoformat(),
            "subscriptionId": demo.SUBSCRIPTION,
            "tenantId": demo.TENANT,
            "identityType": "user",
            "deploymentRevision": "c" * 40,
            "experimentHash": experiment_hash,
            "applicationReachable": True,
            "insightsQuery": True,
            "ingestionQuery": True,
            "workbookRendered": True,
            "accountName": "never-export-this",
        },
    )
    save(
        root / "retention.json",
        {
            "approved": True,
            "retainUntilUtc": (NOW + timedelta(days=14)).isoformat(),
            "materialsReviewed": True,
        },
    )
    save(
        root / "proposal.json",
        {
            "repository": demo.REPOSITORY,
            "revisions": {"baseline": "a" * 40, "candidate": "b" * 40},
            "candidateBoundary": {
                "soleRuntimePath": "hack/sample-multi-agent-workload/src/sample_workload/agents.py",
            },
        },
    )
    for tool in demo.TOOLS:
        save(
            root / "context" / f"{tool}.json",
            {
                **(pricing() if tool == "get_current_pricing" else {}),
                "version": 1,
                "tool": tool,
                "source": "finops-hub",
                "scope": {"resourceId": demo.SCOPE},
                "audit": {"status": "Succeeded"},
                "dataScope": {
                    **(pricing()["dataScope"] if tool == "get_current_pricing" else {}),
                    "deploymentTargets": False,
                },
                "observedAt": (NOW - timedelta(hours=1)).isoformat(),
                "freshness": pricing()["freshness"] if tool == "get_current_pricing" else {},
                "warnings": ["June 2024 sample data, not current sandbox spend."],
                "evidence": [{"seedRunId": "900"}],
            },
        )
    proposal = demo.read(root / "proposal.json")
    proposal["contextRetrieval"] = {
        "workflow": {"runId": 789},
        "responses": [
            {"tool": tool, "sha256": demo.digest(root / "context" / f"{tool}.json")}
            for tool in demo.TOOLS
        ],
    }
    save(root / "proposal.json", proposal)
    case = next(case for case in CASES if case.id == "inventory-below-reorder")
    answer = Answer(
        request_id="synthetic-unit-test",
        answer_status=case.expected_status,
        answer=case.expected_answer,
        data=case.expected_data,
        evidence=Evidence(
            model_mode="azure-openai",
            agent_calls=case.expected_calls,
            row_count=2,
            trace_id="a" * 32,
            model_usage=runs[0].requests[1].model_usage,
        ),
    )
    save(
        root / "opening.json",
        {
            "question": case.question,
            "revision": "c" * 40,
            "capturedUtc": NOW.isoformat(),
            "response": answer.model_dump(mode="json", by_alias=True),
        },
    )
    png = base64.b64decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="
    )
    for name in demo.SHOTS:
        target = root / "screenshots" / name
        target.parent.mkdir(exist_ok=True)
        target.write_bytes(png)
    return root


def mutate(root: Path, name: str, changes: dict[str, Any]) -> None:
    value = demo.read(root / name)
    value.update(changes)
    save(root / name, value)


def test_preparation_reproduces_decision_and_isolates_negative_case(tmp_path: Path) -> None:
    root = inputs(tmp_path)
    original = {path: path.read_bytes() for path in root.rglob("*") if path.is_file()}
    output = tmp_path / "public"
    report = demo.prepare(root, output, QUESTIONS, now=NOW)
    assert report["ready"]
    assert report["decision"] == "accept"
    negative = demo.read(output / "negative.json")
    assert negative["result"]["decision"] == "repeat"
    assert negative["result"]["costChangePercent"] is None
    assert not negative["result"]["evidenceComplete"]
    assert "Synthetic" in negative["label"]
    assert all(path.read_bytes() == value for path, value in original.items())
    assert demo.verify(output) == report
    assert not any(b"never-export-this" in path.read_bytes() for path in output.iterdir())
    assert demo.read(output / "pricing.json")["freshness"] == pricing()["freshness"]


@pytest.mark.parametrize(
    ("name", "changes", "message"),
    [
        ("experiment-run.json", {"repository": {"full_name": "other/repo"}}, "producer"),
        ("experiment-run.json", {"conclusion": "failure"}, "producer"),
        ("experiment-run.json", {"event": "push"}, "producer"),
        ("deployment/readiness.json", {"runAttempt": "2"}, "Deployment"),
        ("experiment/source-verification.json", {"agentCodeChanged": False}, "source"),
        ("experiment/decision.json", {"costChangePercent": "-99"}, "original decision"),
        ("experiment/cleanup.json", {"runId": "999"}, "ownership"),
        ("viewer.json", {"identityType": "servicePrincipal"}, "interactive"),
        ("viewer.json", {"deploymentRevision": "d" * 40}, "interactive"),
        ("proposal.json", {"revisions": {"baseline": "b" * 40, "candidate": "b" * 40}}, "proposal"),
    ],
)
def test_mismatched_evidence_fails_closed(
    tmp_path: Path,
    name: str,
    changes: dict[str, Any],
    message: str,
) -> None:
    root = inputs(tmp_path)
    mutate(root, name, changes)
    with pytest.raises(ValueError, match=message):
        demo.prepare(root, tmp_path / "public", QUESTIONS, now=NOW)
    assert not (tmp_path / "public").exists()


def test_stale_prices_preserve_historical_decision_but_block_recording(tmp_path: Path) -> None:
    root = inputs(tmp_path)
    report = demo.prepare(root, tmp_path / "public", QUESTIONS, now=NOW + timedelta(days=8))
    assert not report["ready"]
    assert report["historicalEvidenceVerified"]
    assert report["decision"] == "accept"
    assert report["currentPriceProblems"]
    assert demo.read(tmp_path / "public/pricing.json")["freshness"] == pricing()["freshness"]


def test_missing_access_and_materials_are_not_success(tmp_path: Path) -> None:
    root = inputs(tmp_path)
    (root / "viewer.json").unlink()
    (root / "opening.json").unlink()
    (root / "screenshots/workbook.png").unlink()
    report = demo.prepare(root, tmp_path / "public", QUESTIONS, now=NOW)
    assert not report["ready"]
    assert any("viewer.json" in value for value in report["problems"])
    assert any("opening.json" in value for value in report["problems"])
    assert any("workbook.png" in value for value in report["problems"])


def test_evaluator_or_conditions_tampering_is_not_a_valid_replay(tmp_path: Path) -> None:
    root = inputs(tmp_path)
    conditions = demo.read(root / "experiment/conditions.json")
    conditions["controller"]["src/sample_workload/experiment.py"] = "0" * 64
    save(root / "experiment/conditions.json", conditions)
    (root / "experiment/conditions.sha256").write_text(
        demo.digest(root / "experiment/conditions.json")
    )
    with pytest.raises(ValueError, match="Evaluator revision"):
        demo.prepare(root, tmp_path / "public", QUESTIONS, now=NOW)


def test_manifest_rejects_modified_and_traversal_files(tmp_path: Path) -> None:
    root = inputs(tmp_path)
    output = tmp_path / "public"
    demo.prepare(root, output, QUESTIONS, now=NOW)
    (output / "comparison.json").write_text("{}")
    with pytest.raises(ValueError, match="integrity"):
        demo.verify(output)
    manifest = demo.read(output / "manifest.json")
    manifest["files"]["comparison.json"] = demo.digest(output / "comparison.json")
    manifest["files"]["../private/viewer.json"] = demo.digest(root / "viewer.json")
    save(output / "manifest.json", manifest)
    with pytest.raises(ValueError, match="integrity"):
        demo.verify(output)


def test_context_must_match_the_actual_recorded_proposal(tmp_path: Path) -> None:
    root = inputs(tmp_path)
    mutate(root, "context/get_cost_summary.json", {"observedAt": NOW.isoformat()})
    with pytest.raises(ValueError, match="original bounded context"):
        demo.prepare(root, tmp_path / "public", QUESTIONS, now=NOW)


def test_context_cannot_silently_change_the_measured_seed(tmp_path: Path) -> None:
    root = inputs(tmp_path)
    name = "context/get_cost_summary.json"
    mutate(root, name, {"evidence": [{"seedRunId": "999"}]})
    proposal = demo.read(root / "proposal.json")
    proposal["contextRetrieval"]["responses"][0]["sha256"] = demo.digest(root / name)
    save(root / "proposal.json", proposal)
    with pytest.raises(ValueError, match="same verified seed"):
        demo.prepare(root, tmp_path / "public", QUESTIONS, now=NOW)


def test_missing_input_cli_reports_failure_without_export(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    import sys

    output = tmp_path / "public"
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "demo",
            "prepare",
            "--input",
            str(tmp_path / "absent"),
            "--output",
            str(output),
        ],
    )
    with pytest.raises(SystemExit) as failure:
        demo.main()
    assert failure.value.code == 2
    assert "Not ready" in capsys.readouterr().err
    assert not output.exists()


def test_guided_presentation_never_opens_links_by_default(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    root = inputs(tmp_path)
    output = tmp_path / "public"
    demo.prepare(root, output, QUESTIONS, now=NOW)

    class Frozen(datetime):
        @classmethod
        def now(cls, tz: Any = None) -> "Frozen":
            return cls.fromtimestamp(NOW.timestamp(), tz=tz)

    monkeypatch.setattr(demo, "datetime", Frozen)
    monkeypatch.setattr(webbrowser, "open", lambda _: pytest.fail("No browser in default mode"))
    demo.show(output, pause=False)
    text = capsys.readouterr().out
    assert "Previously completed" in text
    assert "h09-123" in text
    assert "Synthetic" in text
    assert "3:45-4:30" in text
    monkeypatch.setattr(demo, "datetime", datetime)
    mutate(output, "preparation.json", {"ready": False})
    manifest = demo.read(output / "manifest.json")
    manifest["files"]["preparation.json"] = demo.digest(output / "preparation.json")
    save(output / "manifest.json", manifest)
    with pytest.raises(ValueError, match="Not recording-ready"):
        demo.show(output, pause=False)
