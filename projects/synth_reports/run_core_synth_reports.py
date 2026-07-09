#!/usr/bin/env python3
"""Run RadBuild synthesis reports for the RadHDL core metrics matrix."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def default_radbuild_cli(root: Path) -> Path:
    sibling = root.parent / "RadBuild" / "radbuild" / ".tools" / "v0.2.0" / "radbuild.py"
    if sibling.exists():
        return sibling
    return Path("radbuild")


def load_matrix(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def matrix_commands(args: argparse.Namespace) -> list[tuple[str, str, str, Path, list[str]]]:
    root = repo_root()
    matrix_path = args.matrix.expanduser().resolve()
    matrix = load_matrix(matrix_path)
    radbuild_cli = Path(os.environ.get("RADBUILD_CLI", str(default_radbuild_cli(root)))).expanduser()
    base_command = [sys.executable, str(radbuild_cli)] if radbuild_cli.suffix == ".py" else [str(radbuild_cli)]
    commands: list[tuple[str, str, str, Path, list[str]]] = []
    for core in matrix.get("cores", []):
        module = core["module"]
        for target in matrix.get("targets", []):
            target_id = target["id"]
            part = target["part"]
            summary = root / "projects" / "synth_reports" / module / part / "synth_summary.json"
            command = [
                *base_command,
                "hdl",
                "synth",
                "--top",
                module,
                "--library",
                core.get("library", "work"),
                "--part",
                part,
                "--clock-period",
                str(target["clock_period_ns"]),
                "--clock-port",
                core.get("clock_port", "clk"),
                "--summary-json",
                str(summary.relative_to(root)),
                "--clean",
            ]
            for source in core.get("sources", []):
                command.extend(["--source", source])
            for item in core.get("library_sources", []):
                command.extend(["--library-source", f"{item['library']}={item['source']}"])
            generics = dict(core.get("generics", {}))
            generics.update(dict(core.get("target_generics", {}).get(target_id, {})))
            for key, value in sorted(generics.items()):
                command.extend(["--generic", f"{key}={value}"])
            commands.append((module, target_id, part, summary, command))
    return commands


def run_matrix(args: argparse.Namespace) -> int:
    root = repo_root()
    failed = False
    commands = matrix_commands(args)
    if args.dry_run:
        for _module, _target_id, _part, _summary, command in commands:
            print("+ " + " ".join(command))
        return 0

    runnable = [
        item
        for item in commands
        if not (args.skip_existing and item[3].exists() and json.loads(item[3].read_text(encoding="utf-8")).get("status") == "ok")
    ]
    skipped = len(commands) - len(runnable)
    if skipped:
        print(f"Skipping {skipped} existing successful synthesis summaries.")

    def run_one(item: tuple[str, str, str, Path, list[str]]) -> tuple[tuple[str, str, str, Path, list[str]], int]:
        module, target_id, part, summary, command = item
        print(f"+ [{module} {target_id} {part}] " + " ".join(command), flush=True)
        log_path = summary.parent / "synth_run.log"
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("w", encoding="utf-8") as log:
            completed = subprocess.run(command, cwd=root, check=False, stdout=log, stderr=subprocess.STDOUT)
        return item, completed.returncode

    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as executor:
        future_map = {executor.submit(run_one, item): item for item in runnable}
        for future in as_completed(future_map):
            item, returncode = future.result()
            module, target_id, part, _summary, _command = item
            print(f"= [{module} {target_id} {part}] returncode={returncode}", flush=True)
            failed = failed or returncode != 0
    return 1 if failed else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--matrix",
        type=Path,
        default=Path(__file__).with_name("core_matrix.json"),
        help="Core synthesis matrix JSON.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print commands without running Vivado.")
    parser.add_argument("--jobs", type=int, default=1, help="Number of synthesis jobs to run in parallel.")
    parser.add_argument("--skip-existing", action="store_true", help="Skip summaries that already exist with status ok.")
    return run_matrix(parser.parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
