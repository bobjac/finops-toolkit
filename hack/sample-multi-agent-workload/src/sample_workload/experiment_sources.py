# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

"""Verify exact trusted revisions and immutable workload/evaluation inputs."""

import argparse
import ast
import hashlib
import json
import re
import subprocess

ROOT = "hack/sample-multi-agent-workload/"
PROTECTED = (
    ".dockerignore",
    "Dockerfile",
    "requirements.lock",
    "pyproject.toml",
    "tests/evaluation/questions.json",
    *(
        f"src/sample_workload/{name}.py"
        for name in (
            "__init__",
            "__main__",
            "api",
            "azure_model",
            "container",
            "contracts",
            "database",
            "evaluation",
            "model",
            "telemetry",
        )
    ),
)


def protected_agent_nodes(source: bytes) -> str:
    allowed = ast.dump(
        ast.parse(
            "';'.join(statement for statement in SCHEMA.split(';') "
            "if any(statement.lstrip().startswith(f'CREATE TABLE {table}(') "
            "for table in SCOPES[pattern])) + ';'",
            mode="eval",
        ).body
    )

    class NormalizeSchema(ast.NodeTransformer):
        def visit_Dict(self, node: ast.Dict) -> ast.Dict:
            for index, key in enumerate(node.keys):
                if isinstance(key, ast.Constant) and key.value == "schema":
                    value = node.values[index]
                    if ast.dump(value) == allowed:
                        node.values[index] = ast.Name(id="SCHEMA", ctx=ast.Load())
            return node

    return ast.dump(NormalizeSchema().visit(ast.parse(source)))


def validate_sources(baseline: dict[str, bytes], candidate: dict[str, bytes]) -> dict[str, object]:
    for path in PROTECTED:
        if baseline[path] != candidate[path]:
            raise ValueError(f"Equivalent experiments cannot change protected input: {path}.")
    path = "src/sample_workload/agents.py"
    if protected_agent_nodes(baseline[path]) != protected_agent_nodes(candidate[path]):
        raise ValueError("Candidate changes to agent measurement/correlation logic are forbidden.")
    hashes = {path: hashlib.sha256(baseline[path]).hexdigest() for path in PROTECTED}
    hashes["protectedAgentLogic"] = hashlib.sha256(
        protected_agent_nodes(baseline[path]).encode()
    ).hexdigest()
    return {
        "protectedInputs": hashes,
        "protectedInputsHash": hashlib.sha256(
            json.dumps(hashes, sort_keys=True).encode()
        ).hexdigest(),
        "agentCodeChanged": (
            ast.dump(ast.parse(baseline[path])) != ast.dump(ast.parse(candidate[path]))
        ),
    }


def git(*arguments: str) -> bytes:
    result = subprocess.run(["git", *arguments], capture_output=True, check=False)
    if result.returncode:
        raise ValueError("Source verification failed; use exact revisions on the fork's dev.")
    return result.stdout


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--candidate", required=True)
    args = parser.parse_args()
    if args.baseline == args.candidate:
        raise ValueError("Different exact revisions are required.")
    sources = []
    for revision in (args.baseline, args.candidate):
        if not re.fullmatch(r"[a-f0-9]{40}", revision):
            raise ValueError("Use full commit SHAs, not mutable branch names or expressions.")
        git("merge-base", "--is-ancestor", revision, "origin/dev")
        sources.append(
            {
                path: git("show", f"{revision}:{ROOT}{path}")
                for path in (*PROTECTED, "src/sample_workload/agents.py")
            }
        )
    changes = git("diff", "--name-only", args.baseline, args.candidate, "--", ROOT + "src/")
    allowed = {
        ROOT + "src/sample_workload/" + name + ".py"
        for name in ("agents", "experiment", "experiment_load", "experiment_sources")
    }
    if any(path not in allowed for path in changes.decode().splitlines()):
        raise ValueError("Candidate changes to other runtime modules are forbidden.")
    result = validate_sources(sources[0], sources[1])
    result.update(baselineRevision=args.baseline, candidateRevision=args.candidate)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
