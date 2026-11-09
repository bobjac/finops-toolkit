# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

import argparse
import asyncio
import json
from pathlib import Path

import uvicorn

from .agents import Coordinator
from .api import create_app
from .database import Store, initialize
from .evaluation import evaluate
from .model import DeterministicModel


def main() -> None:
    parser = argparse.ArgumentParser(description="Local synthetic retail sample; no Azure calls.")
    commands = parser.add_subparsers(dest="command", required=True)
    seed = commands.add_parser("initialize")
    seed.add_argument("--database", type=Path, required=True)
    seed.add_argument("--seed", type=int, default=42)
    for name in ("run", "evaluate"):
        command = commands.add_parser(name)
        command.add_argument("--database", type=Path, required=True)
        command.add_argument("--model-mode", choices=["deterministic"], required=True)
        if name == "run":
            command.add_argument("--host", default="127.0.0.1")
            command.add_argument("--port", type=int, default=8000)
        else:
            command.add_argument("--questions", type=Path, required=True)
            command.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "initialize":
        initialize(args.database, args.seed)
        return
    coordinator = Coordinator(Store(args.database), DeterministicModel())
    if args.command == "run":
        uvicorn.run(create_app(coordinator), host=args.host, port=args.port)
        return
    report = asyncio.run(evaluate(coordinator, args.questions))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
