# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

"""Prepare local evidence and guide a read-only recording. Never invoke the workload."""

import argparse
import hashlib
import html
import json
import re
import webbrowser
from copy import deepcopy
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from .contracts import Answer
from .evaluation import GoldenCase, check
from .experiment import Comparison, RunMeasurement, compare, price_rows, utc, validate_definition

REPOSITORY = "bobjac/finops-toolkit"
GITHUB = f"https://github.com/{REPOSITORY}"
SUBSCRIPTION = "6e87e78d-fe02-4f01-bd7b-4f2157eabd5a"
TENANT = "3670e846-58dd-4658-86fb-00e4029045d6"
SCOPE = f"/subscriptions/{SUBSCRIPTION}/resourceGroups/ftk-dto-hack-s-ae46"
TOOLS = (
    "get_cost_summary",
    "get_cost_by_resource",
    "get_optimization_recommendations",
    "get_current_pricing",
)
SHOTS = ("application.png", "workbook.png", "proposal.png")
SCENES = (
    ("0:00-0:35", "Problem and partner value", "application"),
    ("0:35-1:15", "Microsoft technology and baseline", "workbook"),
    ("1:15-2:05", "One bounded proposal and human approval", "diff"),
    ("2:05-3:10", "Measured comparison, not invoice savings", "decision"),
    ("3:10-3:45", "Synthetic missing-price guardrail", "negative"),
    ("3:45-4:30", "Partner reuse, limitations, and evidence", "evidence"),
)


class DemoError(ValueError):
    """An operator-safe preparation diagnostic."""


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise DemoError(message)


def selected(value: dict[str, Any], names: tuple[str, ...]) -> dict[str, Any]:
    return {name: value[name] for name in names if name in value}


def pricing_export(prices: dict[str, Any]) -> dict[str, Any]:
    result = selected(prices, ("tool", "source", "freshness", "dataScope", "warnings", "evidence"))
    result["data"] = {
        "rows": [
            selected(
                row,
                (
                    "Direction",
                    "Price",
                    "MeterId",
                    "Unit",
                    "BlockSize",
                    "Currency",
                    "Region",
                    "Offer",
                    "EffectiveStart",
                    "EffectiveEnd",
                ),
            )
            for row in prices["data"]["rows"]
        ]
    }
    return result


def workflow(value: dict[str, Any], name: str) -> dict[str, Any]:
    require(
        value["repository"]["full_name"] == REPOSITORY
        and value["head_branch"] == "dev"
        and value["event"] == "workflow_dispatch"
        and value["path"] == f".github/workflows/{name}.yml"
        and value["status"] == "completed"
        and value["conclusion"] == "success"
        and re.fullmatch(r"[a-f0-9]{40}", value["head_sha"]) is not None
        and str(value["id"]).isdigit()
        and int(value["run_attempt"]) > 0,
        f"Expected a successful fork/dev {name} producer, not an arbitrary run.",
    )
    return {
        key: value[key]
        for key in ("id", "run_attempt", "head_sha", "created_at", "updated_at", "path")
    }


def inspect_evidence(root: Path, questions: Path, now: datetime) -> dict[str, Any]:
    experiment = root / "experiment"
    producer = workflow(read(root / "experiment-run.json"), "sample-experiment")
    deploy_run = workflow(read(root / "deployment-run.json"), "sandbox-deploy")
    definition = read(experiment / "definition.json")
    revisions = validate_definition(definition)
    verification = read(experiment / "source-verification.json")
    conditions = read(experiment / "conditions.json")
    conditions_hash = digest(experiment / "conditions.json")
    require(
        (experiment / "conditions.sha256").read_text().strip().lower() == conditions_hash,
        "Conditions hash does not match the retained conditions.",
    )
    require(
        verification["baselineRevision"] == revisions["baseline"]
        and verification["candidateRevision"] == revisions["candidate"]
        and verification["agentCodeChanged"] is True
        and conditions["source"] == verification
        and conditions["runtime"]
        == {
            "model": "gpt-5-mini",
            "modelVersion": "2025-08-07",
            "sku": "GlobalStandard",
            "seed": 42,
            "replicas": 1,
            "cpu": 0.25,
            "memory": "0.5Gi",
        }
        and conditions["policy"]
        == {
            key: definition[key]
            for key in ("adapter", "workloadUnit", "scope", "load", "guardrails", "cost", "cleanup")
        }
        and verification["protectedInputsHash"]
        == hashlib.sha256(
            json.dumps(verification["protectedInputs"], sort_keys=True).encode()
        ).hexdigest(),
        "Equivalent source inputs and fixed runtime/guardrails are required.",
    )
    # Historical reevaluation is valid only with the original evaluator and golden cases.
    sample_root = Path(__file__).resolve().parents[2]
    for relative in (
        "src/sample_workload/experiment.py",
        "src/sample_workload/experiment_sources.py",
    ):
        require(
            digest(sample_root / relative).upper() == conditions["controller"][relative].upper(),
            "Evaluator revision differs. Use the recorded controller checkout; do not relabel it.",
        )
    question_hash = digest(questions)
    require(
        verification["protectedInputs"]["tests/evaluation/questions.json"] == question_hash,
        "The golden questions differ from the measured experiment.",
    )
    runs = [RunMeasurement.model_validate(value) for value in read(experiment / "runs.json")]
    cleanup = read(experiment / "cleanup.json")
    require(
        str(cleanup["runId"]) == str(producer["id"])
        and cleanup["verified"] is True
        and not cleanup["failures"]
        and all(run.experiment_id == f"h09-{producer['id']}" for run in runs),
        "Experiment ownership or temporary-app cleanup is not verified.",
    )
    evaluated_at = utc(producer["updated_at"])
    require(
        utc(producer["created_at"]) <= min(run.start_utc for run in runs)
        and max(run.end_utc for run in runs) <= evaluated_at <= now
        and utc(cleanup["completedUtc"]) <= evaluated_at,
        "The measured windows or cleanup are outside the completed producer run.",
    )
    prices = read(experiment / "pricing.json")
    cases = [GoldenCase.model_validate(value) for value in read(questions)]

    def evaluate(pricing: dict[str, Any]) -> Comparison:
        return compare(
            definition,
            runs,
            cases,
            pricing,
            questions_hash=question_hash,
            conditions_hash=conditions_hash,
            cleanup_succeeded=True,
            agent_code_changed=True,
            now=evaluated_at,
        )

    comparison = evaluate(prices)
    require(
        comparison == read(experiment / "decision.json") and comparison["evidenceComplete"],
        "The original decision does not reproduce from complete retained evidence.",
    )
    negative_prices = deepcopy(prices)
    negative_prices["data"]["rows"] = [
        row for row in negative_prices["data"]["rows"] if row["Direction"] != "output"
    ]
    negative = evaluate(negative_prices)
    require(
        negative["decision"] == "repeat" and not negative["evidenceComplete"],
        "The isolated missing-price test did not block a savings decision.",
    )
    readiness = read(root / "deployment" / "readiness.json")
    sample = read(root / "sample" / "deployment-validation.json")
    require(
        readiness["ready"] is True
        and readiness["status"] == "VerifiedAndRetained"
        and str(readiness["runId"]) == str(deploy_run["id"])
        and str(readiness["runAttempt"]) == str(deploy_run["run_attempt"])
        and readiness["revision"] == deploy_run["head_sha"]
        and sample["revision"] == readiness["revision"]
        and str(sample["runId"]) == str(deploy_run["id"])
        and str(sample["runAttempt"]) == str(deploy_run["run_attempt"])
        and sample["subscriptionId"] == SUBSCRIPTION
        and sample["resourceGroup"] == "ftk-dto-hack-s-ae46"
        and sample["liveVerified"] is True,
        "Deployment readiness and live validation must belong to the same successful producer.",
    )
    application = readiness["links"]["application"].rstrip("/")
    require(
        re.fullmatch(
            r"https://ca-ftk-dto-hack-s-ae46\.[a-z0-9-]+\.eastus2\.azurecontainerapps\.io",
            application,
        )
        is not None
        and application == f"https://{sample['outputs']['fqdn']['value']}",
        "The application is not the verified retained sandbox endpoint.",
    )
    workbook = readiness["links"]["workbook"]
    require(
        re.fullmatch(
            re.escape(f"https://portal.azure.com/#@/resource{SCOPE}")
            + r"/providers/Microsoft\.Insights/workbooks/[a-f0-9-]{36}/workbook",
            workbook,
        )
        is not None,
        "The workbook link is outside the approved retained sample.",
    )
    _, price_problems = price_rows(prices, now)
    return {
        "comparison": comparison,
        "contract": {
            "definition": definition,
            "runtime": selected(
                conditions["runtime"],
                ("model", "modelVersion", "sku", "seed", "replicas", "cpu", "memory"),
            ),
            "conditionsHash": conditions_hash,
            "protectedInputsHash": verification["protectedInputsHash"],
            "controllerRevision": producer["head_sha"],
        },
        "negative": {
            "label": "Synthetic missing-output-meter test, not a second live experiment",
            "evaluationClockUtc": evaluated_at.isoformat(),
            "clockMeaning": "Replay at the original run completion; original price dates unchanged",
            "mutation": "Removed output meter from an in-memory copy only",
            "result": negative,
        },
        "pricing": prices,
        "producer": producer,
        "seedRunId": str(read(experiment / "seed-run.json")["id"]),
        "deployment": deploy_run,
        "deploymentRevision": readiness["revision"],
        "retainedResourceExpiryUtc": sample["expiresOn"],
        "currentPriceProblems": price_problems,
        "experimentId": runs[0].experiment_id,
        "experimentHash": hashlib.sha256(runs[0].experiment_id.encode()).hexdigest(),
        "startUtc": min(run.start_utc for run in runs).isoformat(),
        "endUtc": max(run.end_utc for run in runs).isoformat(),
        "links": {
            "application": application + "/docs",
            "workbook": workbook,
            "diff": f"{GITHUB}/compare/{revisions['baseline']}...{revisions['candidate']}",
            "experiment": (
                f"{GITHUB}/actions/runs/{producer['id']}/attempts/{producer['run_attempt']}"
            ),
            "deployment": (
                f"{GITHUB}/actions/runs/{deploy_run['id']}/attempts/{deploy_run['run_attempt']}"
            ),
        },
    }


def inspect_materials(
    root: Path,
    evidence: dict[str, Any],
    questions: Path,
    now: datetime,
    *,
    archived: bool = False,
) -> tuple[dict[str, Any], list[str]]:
    problems = []
    materials: dict[str, Any] = {}
    for name in ("proposal",) if archived else ("viewer", "retention", "opening", "proposal"):
        path = root / f"{name}.json"
        if not path.is_file():
            problems.append(f"Missing {name}.json; follow the off-camera command sheet.")
            continue
        value = read(path)
        if name == "viewer":
            require(
                value["subscriptionId"] == SUBSCRIPTION
                and value["tenantId"] == TENANT
                and value["identityType"] == "user"
                and value["deploymentRevision"] == evidence["deploymentRevision"]
                and value["experimentHash"] == evidence["experimentHash"],
                "Viewer receipt is not the intended interactive account, revision, or experiment.",
            )
            if not timedelta(0) <= now - utc(value["checkedUtc"]) <= timedelta(hours=1):
                problems.append("Viewer access receipt is older than one hour or in the future.")
            if not all(
                value.get(key) is True
                for key in (
                    "applicationReachable",
                    "insightsQuery",
                    "ingestionQuery",
                    "workbookRendered",
                )
            ):
                problems.append(
                    "Interactive app, telemetry, Ingestion, or workbook checks are missing."
                )
            materials[name] = {
                key: value[key]
                for key in ("checkedUtc", "identityType", "deploymentRevision", "experimentHash")
            }
        elif name == "retention":
            require(
                value["approved"] is True and utc(value["retainUntilUtc"]) > now,
                "Record the separately approved evidence/resource retention end time.",
            )
            materials[name] = {
                "retainUntilUtc": value["retainUntilUtc"],
                "automaticShutdown": False,
                "cleanupPlan": "Separate approved Sample teardown, then Foundation teardown",
            }
            if value.get("materialsReviewed") is not True:
                problems.append(
                    "Privately review the exported text and screenshots before recording."
                )
        elif name == "opening":
            answer = Answer.model_validate(value["response"])
            case = next(
                GoldenCase.model_validate(case)
                for case in read(questions)
                if case["id"] == "inventory-below-reorder"
            )
            require(
                value["question"] == case.question
                and value["revision"] == evidence["deploymentRevision"]
                and utc(value["capturedUtc"]) <= now
                and answer.evidence.model_mode == "azure-openai"
                and len(answer.evidence.model_usage) == 4
                and re.fullmatch(r"[a-f0-9]{32}", answer.evidence.trace_id or "") is not None
                and not check(case, answer),
                "Opening evidence must be the genuine, correct, separately approved live request.",
            )
            materials[name] = {
                "label": "Previously captured live request; separate from the measured experiment",
                "capturedUtc": value["capturedUtc"],
                "revision": value["revision"],
                "question": case.question,
                "data": answer.data.model_dump(),
                "traceId": answer.evidence.trace_id,
                "agentCalls": answer.evidence.agent_calls,
                "modelUsage": [
                    item.model_dump(by_alias=True) for item in answer.evidence.model_usage
                ],
            }
        else:
            baseline, _, candidate = evidence["comparison"]["runs"]
            require(
                value["revisions"]["baseline"] == baseline["revision"]
                and value["revisions"]["candidate"] == candidate["revision"]
                and value["repository"] == REPOSITORY
                and value["candidateBoundary"]["soleRuntimePath"]
                == "hack/sample-multi-agent-workload/src/sample_workload/agents.py",
                "The recorded proposal does not match the measured revisions and bounded change.",
            )
            context_run = workflow(read(root / "context-run.json"), "sandbox-context")
            require(
                str(value["contextRetrieval"]["workflow"]["runId"]) == str(context_run["id"]),
                "The proposal context belongs to a different protected retrieval.",
            )
            references = {
                item["tool"]: item["sha256"] for item in value["contextRetrieval"]["responses"]
            }
            require(
                set(references) == set(TOOLS), "The proposal must reference all four context tools."
            )
            contexts = []
            for tool in TOOLS:
                context = read(root / "context" / f"{tool}.json")
                require(
                    context["tool"] == tool
                    and context["version"] == 1
                    and context["scope"]["resourceId"] == SCOPE
                    and context["audit"]["status"] == "Succeeded"
                    and context["dataScope"]["deploymentTargets"] is False
                    and utc(context_run["created_at"])
                    <= utc(context["observedAt"])
                    <= utc(context_run["updated_at"])
                    <= utc(evidence["startUtc"])
                    and digest(root / "context" / f"{tool}.json") == references[tool],
                    "All four original bounded context envelopes must precede the experiment.",
                )
                require(
                    any(
                        str(item.get("seedRunId")) == evidence["seedRunId"]
                        for item in context["evidence"]
                    ),
                    "Proposal context and measurement must use the same verified seed producer.",
                )
                if tool == "get_current_pricing":
                    _, problems_at_measurement = price_rows(context, utc(evidence["startUtc"]))
                    require(
                        not problems_at_measurement,
                        "The proposal's original required prices were stale at measurement.",
                    )
                contexts.append(
                    {
                        key: context[key]
                        for key in (
                            "tool",
                            "source",
                            "scope",
                            "observedAt",
                            "freshness",
                            "dataScope",
                            "warnings",
                            "evidence",
                        )
                    }
                )
            materials[name] = {
                "label": "Recorded proposal, not a newly created experiment",
                "change": "Narrow both specialist schemas to complete SCOPES[pattern] tables",
                "revisions": selected(value["revisions"], ("baseline", "candidate")),
                "context": contexts,
                "sourceSha256": digest(path),
            }
    for name in () if archived else SHOTS:
        path = root / "screenshots" / name
        if not path.is_file():
            problems.append(f"Missing reviewed screenshot: {name}.")
    return materials, problems


def require_new_output(root: Path, output: Path) -> None:
    require(not output.exists(), "Use a new evidence directory; never overwrite a prior package.")
    require(
        not output.resolve().is_relative_to(root.resolve()),
        "Keep the presentation package separate from the private original evidence directory.",
    )


def prepare(root: Path, output: Path, questions: Path, *, now: datetime) -> dict[str, Any]:
    require_new_output(root, output)
    evidence = inspect_evidence(root, questions, now)
    materials, problems = inspect_materials(root, evidence, questions, now)
    problems.extend(evidence["currentPriceProblems"])
    if utc(evidence["retainedResourceExpiryUtc"]) <= now:
        problems.append("Retained resource expiration has passed; obtain a new retention decision.")
    output.mkdir(parents=True)
    write(output / "comparison.json", evidence["comparison"])
    write(output / "experiment.json", evidence["contract"])
    write(output / "negative.json", evidence["negative"])
    write(output / "pricing.json", pricing_export(evidence["pricing"]))
    write(output / "materials.json", materials)
    report = {
        "version": 1,
        "ready": not problems,
        "historicalEvidenceVerified": True,
        "label": "Previously completed live experiment; not a new experiment or invoice savings",
        "preparedUtc": now.isoformat(),
        "problems": problems,
        "experimentId": evidence["experimentId"],
        "experimentHash": evidence["experimentHash"],
        "startUtc": evidence["startUtc"],
        "endUtc": evidence["endUtc"],
        "deploymentRevision": evidence["deploymentRevision"],
        "retainedResourceExpiryUtc": evidence["retainedResourceExpiryUtc"],
        "producer": evidence["producer"],
        "deployment": evidence["deployment"],
        "links": evidence["links"],
        "decision": evidence["comparison"]["decision"],
        "currentPriceProblems": evidence["currentPriceProblems"],
        "trust": "Operator-downloaded originals; hashes establish integrity, not signatures",
        "issueComplete": False,
        "remainingHumanGates": [
            "Accepted off-camera clean rebuild and scoped teardown receipts",
            "Timed rehearsal and sanitized playable 3-5 minute recording",
            "Verified portal requirements and submission confirmation",
        ],
    }
    write(output / "preparation.json", report)
    for name in SHOTS:
        source = root / "screenshots" / name
        if source.is_file():
            require(
                source.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"), "Screenshots must be PNG."
            )
            (output / name).write_bytes(source.read_bytes())
    sections = [
        ("Preparation", report),
        ("Previously captured application answer", materials.get("opening", "Not captured")),
        ("Recorded proposal and context", materials.get("proposal", "Not retained")),
        ("Original measured comparison", evidence["comparison"]),
        ("Pricing with original dates", read(output / "pricing.json")),
        ("Synthetic missing-price case", evidence["negative"]),
    ]
    page = (
        '<!doctype html><meta charset="utf-8"><title>FinOps PoC evidence</title>'
        "<style>body{font:20px system-ui;max-width:1100px;margin:2em auto;padding:1em}"
        "pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f3f3f3;padding:1em}"
        "h1,h2{color:#174578}a{margin-right:1em}</style>"
        "<h1>FinOps design-time optimizer</h1>"
        f"<p><strong>{'Ready' if report['ready'] else 'Not recording-ready'}</strong></p>"
        "<p>Previously completed experiment. "
        "Public-retail model-only estimates, not invoice savings. Synthetic retail data.</p>"
    )
    page += (
        f"<h2 id='comparison'>Original decision: {html.escape(report['decision'].upper())}</h2>"
        "<p>Estimated USD per 1,000 successful evaluated answers. "
        "All consumed measured calls enter the numerator.</p>"
        "<table cellpadding='8'><tr><th>Variant/pass</th><th>USD/1,000 answers</th>"
        "<th>Quality</th><th>Errors</th><th>Price coverage</th><th>p95 ms</th></tr>"
    )
    for run in evidence["comparison"]["runs"]:
        values = (
            f"{run['variant']} {run['repetition']}",
            str(run["costPer1000SuccessfulAnswersUsd"]),
            f"{run['qualityPercent']}%",
            f"{run['errorRatePercent']}%",
            f"{run['priceCoveragePercent']}%",
            f"{run['p95LatencyMs']:.1f}",
        )
        page += "<tr>" + "".join(f"<td>{html.escape(value)}</td>" for value in values) + "</tr>"
    page += "</table>"
    for index, (title, value) in enumerate(sections):
        page += (
            f"<h2 id='section-{index}'>{html.escape(title)}</h2>"
            f"<pre>{html.escape(json.dumps(value, indent=2))}</pre>"
        )
    page += (
        "<h2>Equivalent conditions and fixed guardrails</h2>"
        f"<pre>{html.escape(json.dumps(evidence['contract'], indent=2))}</pre>"
    )
    page += "<h2>Verified links</h2>"
    for name, url in evidence["links"].items():
        page += f'<a href="{html.escape(url, quote=True)}">{html.escape(name)}</a>'
    (output / "index.html").write_text(page + "\n", encoding="utf-8")
    seal_package(root, output)
    return report


def seal_package(root: Path, output: Path) -> None:
    write(
        output / "manifest.json",
        {
            "version": 1,
            "files": {path.name: digest(path) for path in sorted(output.iterdir())},
            "originalFiles": {
                str(path.relative_to(root)): digest(path)
                for path in [
                    root / "experiment-run.json",
                    root / "deployment-run.json",
                    root / "context-run.json",
                    root / "deployment/readiness.json",
                    root / "sample/deployment-validation.json",
                    *(
                        root / "experiment" / name
                        for name in (
                            "definition.json",
                            "source-verification.json",
                            "conditions.json",
                            "conditions.sha256",
                            "runs.json",
                            "cleanup.json",
                            "pricing.json",
                            "decision.json",
                            "seed-run.json",
                        )
                    ),
                    *(
                        root / f"{name}.json"
                        for name in ("viewer", "retention", "opening", "proposal")
                    ),
                    *(root / "context" / f"{tool}.json" for tool in TOOLS),
                ]
                if path.is_file() and not path.is_symlink()
            },
            "privacy": (
                "Exports omit account identity and raw spans. Review images and text privately."
            ),
        },
    )


def archive_table(headers: tuple[str, ...], rows: list[list[object]]) -> str:
    return (
        "<table><thead><tr>"
        + "".join(f"<th>{html.escape(value)}</th>" for value in headers)
        + "</tr></thead><tbody>"
        + "".join(
            "<tr>" + "".join(f"<td>{html.escape(str(value))}</td>" for value in row) + "</tr>"
            for row in rows
        )
        + "</tbody></table>"
    )


def prepare_archive(root: Path, output: Path, questions: Path, *, now: datetime) -> dict[str, Any]:
    """Reproduce a historical result, without asserting current Azure readiness."""
    require_new_output(root, output)
    evidence = inspect_evidence(root, questions, now)
    materials, problems = inspect_materials(root, evidence, questions, now, archived=True)
    require(not problems, "The original recorded proposal and context are required for an archive.")
    comparison = evidence["comparison"]
    runs = comparison["runs"]
    baseline = sum(Decimal(run["costPer1000SuccessfulAnswersUsd"]) for run in runs[:2]) / 2
    candidate = Decimal(runs[2]["costPer1000SuccessfulAnswersUsd"])
    decision = comparison["decision"].upper()
    result = f"Original decision: {decision}"
    change = comparison["costChangePercent"]
    if decision == "ACCEPT" and change is not None:
        result += f" | {-Decimal(change):.2f}% lower estimated model-only unit cost"
    case = next(
        GoldenCase.model_validate(value)
        for value in read(questions)
        if value["id"] == "inventory-below-reorder"
    )
    measurements = [
        RunMeasurement.model_validate(value) for value in read(root / "experiment/runs.json")
    ]
    inventory = next(
        request
        for run in measurements
        if run.variant == "candidate"
        for request in run.requests
        if request.case_id == case.id
    )
    request_summary = {
        "label": "Retained evaluation metadata, not reconstructed answer text",
        "question": case.question,
        "answerStatus": inventory.answer_status,
        "httpStatus": inventory.http_status,
        "evaluationPassed": not inventory.failures,
        "agentCalls": inventory.agent_calls,
        "modelCalls": len(inventory.model_usage),
    }
    proposal = materials["proposal"]
    freshness = evidence["pricing"]["freshness"]
    cost_table = archive_table(
        ("Pass", "USD / 1,000 answers", "Quality", "HTTP errors", "Prices", "p95 ms"),
        [
            [
                f"{run['variant']} {run['repetition']}",
                f"{Decimal(run['costPer1000SuccessfulAnswersUsd']):.4f}",
                f"{run['qualityPercent']:g}%",
                f"{run['errorRatePercent']:g}%",
                f"{run['priceCoveragePercent']:g}%",
                f"{run['p95LatencyMs']:.1f}",
            ]
            for run in runs
        ],
    )
    usage_table = archive_table(
        ("Pass", "Input tokens", "Cached input", "Output tokens", "Model calls"),
        [
            [
                f"{run['variant']} {run['repetition']}",
                run["tokens"]["input"],
                run["tokens"]["cachedInput"],
                run["tokens"]["output"],
                run["modelCalls"],
            ]
            for run in runs
        ],
    )
    titles = (
        "A completed experiment, not another run",
        "Azure usage, retained from the real measurement",
        "One bounded, human-approved proposal",
        result,
        "Missing prices must not become zero cost",
        "Traceable evidence and clear limits",
    )
    bodies = (
        f"<p class='lead'>{html.escape(case.question)}</p>"
        + archive_table(
            ("Candidate inventory case", "Retained result"),
            [
                ["HTTP status", inventory.http_status],
                ["Answer status", inventory.answer_status],
                ["Evaluation", "Passed" if not inventory.failures else "Failed"],
                ["Measured model calls", len(inventory.model_usage)],
            ],
        )
        + "<p>Agents: "
        + html.escape(" > ".join(inventory.agent_calls))
        + "</p><p class='note'>Evaluation metadata from the completed experiment. "
        "The original response text and inventory rows were not archived; "
        "this presentation does not recreate them.</p>",
        "<p class='lead'>Azure Container Apps > Azure OpenAI > Application Insights<br>"
        "FinOps hub / Azure Data Explorer > pricing and read-only context</p>"
        + usage_table
        + "<p class='note'>Archived measured usage, not a live workbook or new telemetry. "
        "Two baseline passes and one candidate pass used the same seven golden questions.</p>",
        "<p class='lead'>Send each specialist only its approved, complete table definitions.</p>"
        "<p>Both schema arguments changed in <code>agents.py</code>. "
        "Model, data, agent topology, evaluator, and guardrails stayed fixed.</p>"
        "<p>Four bounded, read-only context tools:</p><ul>"
        + "".join(f"<li>{html.escape(context['tool'])}</li>" for context in proposal["context"])
        + "</ul><p class='revision'>Baseline: "
        + html.escape(proposal["revisions"]["baseline"])
        + "<br>Candidate: "
        + html.escape(proposal["revisions"]["candidate"])
        + "</p>",
        cost_table + f"<p>Baseline mean: USD {baseline:.4f}; candidate: USD {candidate:.4f} "
        "per 1,000 successful evaluated answers.</p>"
        "<p>All measured model consumption enters the numerator. Each pass evaluated "
        f"{runs[0]['requestCount']} questions, with {runs[0]['successfulAnswers']} "
        f"successful answers and {runs[0]['expectedNonAnswers']} expected nonanswers.</p>"
        "<p class='note'>Accept requires 100% quality, zero HTTP errors, complete prices, "
        "at most 20% p95 regression, and improvement above both 5% and baseline cost variation. "
        "Original baseline cost variation: "
        + html.escape(str(comparison["baselineCostSpreadPercent"]))
        + "%.</p>",
        "<p class='lead'>Synthetic replay: remove the output-token meter from a copy.</p>"
        "<p>Unchanged evaluator, original evaluation clock, unchanged original price dates.</p>"
        "<p class='result'>"
        + html.escape(evidence["negative"]["result"]["decision"].upper())
        + " | Incomplete evidence | No accepted saving</p>"
        "<p>No model call, live price change, or deployed-app change. "
        "The original experiment decision remains "
        + html.escape(decision)
        + ".</p><p class='note'>This is an isolated synthetic negative case, "
        "not a second live experiment and not a live incident.</p>",
        "<p class='lead'>Reuse the sample, context adapters, protected experiment, "
        "evaluator, and evidence handoff.</p>"
        "<p>Measured UTC: "
        + html.escape(evidence["startUtc"])
        + "<br>through "
        + html.escape(evidence["endUtc"])
        + "</p><p>Original pricing as of: "
        + html.escape(str(freshness["pricingAsOf"]))
        + "<br>Original seven-day price freshness cutoff: "
        + html.escape((utc(freshness["pricingAsOf"]) + timedelta(days=7)).isoformat())
        + "</p><p class='note'>Historical prices, not current prices or invoice savings. "
        "Small sequential PoC; infrastructure, telemetry, builds, and warm-up are excluded. "
        "Experiment temporary-app cleanup was verified in the retained receipt. "
        "This deck does not prove a new clean rebuild or retained-sandbox teardown, "
        "or authorize either operation.</p>"
        "<p>Package hashes: <a href='manifest.json'>manifest</a>. "
        "Hashes establish local integrity, not an independent signature.</p>",
    )
    narration = (
        "An AI assistant can give the right answer and still use more context than it needs. "
        "This synthetic retail example asks which products are below their reorder point. "
        "The real experiment has already completed. Here is its retained inventory evaluation: "
        "the HTTP and answer status, evaluation result, and cooperating agents. The original "
        "response text was not archived, so I am not recreating a chat answer. Everything "
        "in this walkthrough is archived evidence, not a new model request.",
        "The sample uses Azure Container Apps and Azure OpenAI. Application Insights captures "
        "correlated model usage, while the FinOps hub in Azure Data Explorer supplies pricing "
        "and read-only context. These are the actual retained token counts and model calls, "
        "not a live workbook. The experiment fixed the data, model, seven questions, pacing, "
        "and evaluation rules, then measured the baseline twice before the candidate. "
        "Historical sample costs are context, not current sandbox spend.",
        "The design-time optimizer used four bounded, read-only tools: cost summary, resource "
        "costs, cached recommendations, and current pricing. The recorded proposal narrowed "
        "both specialist schema arguments to the complete table definitions approved for "
        "that question. The model, data, agent topology, evaluator, and guardrails stayed "
        "fixed. The context predates the measurement, and the exact revisions are retained. "
        "Publication, deployment, paid traffic, and cleanup have separate human approvals. "
        "This is not an autonomous production change.",
        "The denominator is successful evaluated answers, not model calls. All measured "
        "consumption remains in the numerator, including nonanswers or failures. Acceptance "
        "requires full quality, zero HTTP errors, complete prices, and no more than twenty "
        "percent p95 latency regression. Cost improvement must exceed both five percent "
        "and baseline variation. "
        f"The original decision was {decision}. Baseline mean cost was {baseline:.4f} "
        f"and candidate cost was {candidate:.4f} US dollars per one thousand successful "
        f"evaluated answers. {result}. This is a small sequential proof of concept, "
        "not a statistically powered benchmark or an invoice saving.",
        "This synthetic negative test removes the output-token meter from an isolated copy. "
        "The unchanged evaluator uses the original evaluation time and unchanged price dates. "
        "The result is repeat with incomplete evidence. Unknown cost does not become zero. "
        "No live price, deployed app, or original decision changed.",
        "A partner can reuse the standalone sample, bounded context adapters, protected "
        "experiment, evaluator, and evidence handoff with another approved workload. The "
        "value is a traceable design-time decision, including reasons to reject or repeat. "
        "The original measurement and price dates remain visible. Estimates exclude "
        "infrastructure, telemetry, builds, and warm-up. This offline presentation does not "
        "prove a new rebuild or retained-sandbox teardown. Resources still retained can "
        "remain billable until separately approved cleanup. This is a working proof of "
        "concept, not a production-ready autonomous optimizer.",
    )
    output.mkdir(parents=True)
    report = {
        "version": 1,
        "mode": "archived",
        "ready": False,
        "archiveReady": True,
        "historicalEvidenceVerified": True,
        "issueComplete": False,
        "label": "Archived experiment walkthrough; not live readiness or current-price savings",
        "preparedUtc": now.isoformat(),
        "experimentId": evidence["experimentId"],
        "producer": evidence["producer"],
        "decision": comparison["decision"],
        "startUtc": evidence["startUtc"],
        "endUtc": evidence["endUtc"],
        "currentPriceProblems": evidence["currentPriceProblems"],
        "limitations": [
            "No new model requests, Azure queries, deployments, or cleanup.",
            "Original answer text and rows are not reconstructed.",
            "Live access, retention approvals, clean rebuild, recording, and submission "
            "are not attested by this archive.",
        ],
    }
    for name, value in (
        ("preparation.json", report),
        ("comparison.json", comparison),
        ("experiment.json", evidence["contract"]),
        ("negative.json", evidence["negative"]),
        ("pricing.json", pricing_export(evidence["pricing"])),
        ("materials.json", materials),
        ("request-summary.json", request_summary),
    ):
        write(output / name, value)
    filenames = ["index.html", *(f"scene-{number}.html" for number in range(2, 7))]
    style = (
        "<style>body{margin:0;background:#f6f8fc;color:#17233b;font:18px system-ui}"
        "main{box-sizing:border-box;max-width:1180px;margin:auto;padding:20px 28px;"
        "min-height:100vh;display:flex;flex-direction:column}"
        "header,.note{font-size:15px;color:#425675}header{border-bottom:2px solid #1976c9;"
        "padding-bottom:10px}h1{font-size:30px;line-height:1.2;color:#123e70}"
        "article{flex:1}.lead,.result{font-size:24px;color:#123e70}.revision{font:15px monospace}"
        "table{width:100%;border-collapse:collapse;background:white}th,td{text-align:left;"
        "padding:9px;border-bottom:1px solid #d5deec}th{font-size:15px}"
        "li{margin:5px 0}nav{display:flex;align-items:center;justify-content:space-between;"
        "gap:20px;border-top:1px solid #b7c8df;padding-top:12px;margin-top:12px}"
        "a{color:#124f91}nav a{padding:10px 15px;background:#dcecff;border-radius:6px}"
        "@media print{main{min-height:0}nav{display:none}section{break-inside:avoid}}</style>"
    )
    for index, (title, body, filename) in enumerate(zip(titles, bodies, filenames, strict=True)):
        previous = filenames[max(0, index - 1)]
        following = filenames[index + 1] if index < 5 else filenames[0]
        page = (
            '<!doctype html><html lang="en"><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1">'
            '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; '
            "style-src 'unsafe-inline'; img-src 'self'; base-uri 'none'\">"
            f"<title>Archived FinOps demo - scene {index + 1}</title>{style}<main>"
            "<header>Archived real experiment | Synthetic retail data | "
            "Public-retail model-only estimates | No live requests</header>"
            f"<article><h1>{html.escape(title)}</h1>{body}</article>"
            f"<nav><a href='{previous}'>Previous scene</a>"
            f"<span>Scene {index + 1} of 6</span>"
            f"<a href='{following}'>{'Next scene' if index < 5 else 'Start again'}</a>"
            "</nav></main></html>"
        )
        (output / filename).write_text(page + "\n", encoding="utf-8")
    script = (
        '<!doctype html><html lang="en"><meta charset="utf-8">'
        f"<title>Archived demo narration</title>{style}<main>"
        "<h1>Your recording script</h1><p>Target 4 minutes 30 seconds. "
        "Read from paper or a second screen outside the recorded area.</p>"
        + "".join(
            f"<section><h2>{SCENES[index][0]} - {html.escape(title)}</h2>"
            f"<p>{html.escape(words)}</p></section>"
            for index, (title, words) in enumerate(zip(titles, narration, strict=True))
        )
        + "</main></html>"
    )
    (output / "narration.html").write_text(script + "\n", encoding="utf-8")
    seal_package(root, output)
    return report


def verify(directory: Path) -> dict[str, Any]:
    manifest = read(directory / "manifest.json")
    required = {
        "preparation.json",
        "comparison.json",
        "experiment.json",
        "negative.json",
        "pricing.json",
        "materials.json",
        "index.html",
    }
    require(
        manifest["version"] == 1 and required <= set(manifest["files"]),
        "The evidence manifest is missing required presentation files.",
    )
    for name, expected in manifest["files"].items():
        path = directory / name
        require(
            Path(name).name == name
            and not path.is_symlink()
            and path.is_file()
            and digest(path) == expected,
            "Evidence integrity check failed; stop and re-export.",
        )
    return dict(read(directory / "preparation.json"))


def show(directory: Path, *, pause: bool = True, open_links: bool = False) -> None:
    report = verify(directory)
    require(
        report["ready"] is True, "Not recording-ready. Resolve preparation.json problems first."
    )
    require(
        timedelta(0) <= datetime.now(UTC) - utc(report["preparedUtc"]) <= timedelta(hours=1),
        "Preparation expired. Rerun read-only preparation before recording.",
    )
    now = datetime.now(UTC)
    materials = read(directory / "materials.json")
    _, price_problems = price_rows(read(directory / "pricing.json"), now)
    require(
        not price_problems
        and timedelta(0) <= now - utc(materials["viewer"]["checkedUtc"]) <= timedelta(hours=1)
        and utc(materials["retention"]["retainUntilUtc"]) > now
        and utc(report["retainedResourceExpiryUtc"]) > now,
        "Prices, access, or retention expired. Rerun preparation; do not edit dates.",
    )
    print(
        f"{report['label']}\nExperiment: {report['experimentId']}\n"
        f"Workbook selector: {report['experimentHash']}\n"
        f"UTC window: {report['startUtc']} through {report['endUtc']}\n"
        f"Decision: {report['decision'].upper()}\nEvidence: {directory.resolve()}"
    )
    links = {
        **report["links"],
        "decision": (directory / "index.html").resolve().as_uri() + "#comparison",
        "negative": (directory / "index.html").resolve().as_uri() + "#section-5",
        "evidence": (directory / "index.html").resolve().as_uri(),
    }
    for timing, title, target in SCENES:
        print(f"\n{timing} | {title}\n{links[target]}")
        if open_links:
            url = links[target]
            require(urlparse(url).scheme in ("https", "file"), "Unsafe presentation link.")
            require(webbrowser.open(url), "The browser did not open. Use the printed link.")
        if pause:
            input(
                "Press Enter for the next scene. No Azure operations or model requests are sent. "
            )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("prepare", "archive"):
        preparation = commands.add_parser(name)
        preparation.add_argument("--input", type=Path, required=True)
        preparation.add_argument("--output", type=Path, required=True)
        preparation.add_argument(
            "--questions",
            type=Path,
            default=Path("hack/sample-multi-agent-workload/tests/evaluation/questions.json"),
        )
    for command in ("show", "verify"):
        child = commands.add_parser(command)
        child.add_argument("--directory", type=Path, required=True)
        if command == "show":
            child.add_argument("--no-pause", action="store_true")
            child.add_argument("--open-links", action="store_true")
    args = parser.parse_args()
    try:
        if args.command in ("prepare", "archive"):
            export = prepare_archive if args.command == "archive" else prepare
            report = export(args.input, args.output, args.questions, now=datetime.now(UTC))
            print(json.dumps(report, indent=2))
            if not report.get("archiveReady", report["ready"]):
                raise SystemExit(2)
        elif args.command == "verify":
            print(json.dumps(verify(args.directory), indent=2))
        else:
            show(args.directory, pause=not args.no_pause, open_links=args.open_links)
    except DemoError as error:
        parser.exit(2, f"Not ready: {error}\n")
    except (OSError, ValueError, KeyError, TypeError, StopIteration):
        parser.exit(
            2,
            "Not ready: missing, inconsistent, or invalid evidence. "
            "Check the command sheet; no live fallback was attempted.\n",
        )


if __name__ == "__main__":
    main()
