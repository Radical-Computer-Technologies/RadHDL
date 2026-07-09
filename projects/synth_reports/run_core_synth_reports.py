#!/usr/bin/env python3
"""Run RadBuild synthesis reports for the RadHDL core metrics matrix."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def default_radbuild_cli(root: Path) -> Path:
    sibling = root.parent / "RadBuild" / "radbuild" / ".tools" / "v0.2.0" / "radbuild.py"
    if sibling.exists():
        return sibling
    return Path("radbuild")


def load_matrix(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def run_matrix(args: argparse.Namespace) -> int:
    root = repo_root()
    matrix_path = args.matrix.expanduser().resolve()
    matrix = load_matrix(matrix_path)
    radbuild_cli = Path(os.environ.get("RADBUILD_CLI", str(default_radbuild_cli(root)))).expanduser()
    base_command = [sys.executable, str(radbuild_cli)] if radbuild_cli.suffix == ".py" else [str(radbuild_cli)]
    failed = False
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
            generics = dict(core.get("generics", {}))
            generics.update(dict(core.get("target_generics", {}).get(target_id, {})))
            for key, value in sorted(generics.items()):
                command.extend(["--generic", f"{key}={value}"])
            print("+ " + " ".join(command))
            if not args.dry_run:
                completed = subprocess.run(command, cwd=root, check=False)
                failed = failed or completed.returncode != 0
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
    return run_matrix(parser.parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
