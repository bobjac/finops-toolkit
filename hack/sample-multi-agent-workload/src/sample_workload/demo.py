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
    root: Path, evidence: dict[str, Any], questions: Path, now: datetime
) -> tuple[dict[str, Any], list[str]]:
    problems = []
    materials: dict[str, Any] = {}
    for name in ("viewer", "retention", "opening", "proposal"):
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
    for name in SHOTS:
        path = root / "screenshots" / name
        if not path.is_file():
            problems.append(f"Missing reviewed screenshot: {name}.")
    return materials, problems


def prepare(root: Path, output: Path, questions: Path, *, now: datetime) -> dict[str, Any]:
    require(not output.exists(), "Use a new evidence directory; never overwrite a prior package.")
    require(
        not output.resolve().is_relative_to(root.resolve()),
        "Keep the presentation package separate from the private original evidence directory.",
    )
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
    preparation = commands.add_parser("prepare")
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
        if args.command == "prepare":
            report = prepare(args.input, args.output, args.questions, now=datetime.now(UTC))
            print(json.dumps(report, indent=2))
            if not report["ready"]:
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
