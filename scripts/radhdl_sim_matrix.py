#!/usr/bin/env python3
"""Run RadHDL primitive simulation smoke tests across supported simulator modes."""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BUILD = ROOT / ".radmeta" / "sim-matrix"

PRIMITIVE_VHDL = [
    "common/hdl/ecp5/radhdl_ecp5_dp16kd_18x1024.vhd",
    "common/hdl/src/radhdl_cdc.vhd",
    "common/hdl/src/radhdl_lattice_tdp_ram.vhd",
    "common/hdl/src/radhdl_lattice_ram.vhd",
    "common/hdl/src/radhdl_ram.vhd",
    "common/hdl/src/radhdl_fifo_bram_sync.vhd",
    "common/hdl/src/radhdl_fifo_sync.vhd",
]

XILINX_WRAPPER_VHDL = [
    "common/hdl/src/radhdl_xilinx_ram.vhd",
    "common/hdl/src/radhdl_xilinx_fifo_sync.vhd",
    "common/hdl/src/radhdl_ram.vhd",
    "common/hdl/src/radhdl_fifo_sync.vhd",
]

TESTBENCHES = {
    "ram": {
        "top": "tb_radhdl_ram_vendor",
        "file": "common/hdl/testbenches/tb_radhdl_ram_vendor.vhd",
        "ghdl_marker": "RADHDL_RAM_LATTICE_GHDL_OK",
        "xsim_marker": "RADHDL_RAM_XILINX_XPM_XSIM_OK",
    },
    "fifo-sync": {
        "top": "tb_radhdl_fifo_sync_vendor",
        "file": "common/hdl/testbenches/tb_radhdl_fifo_sync_vendor.vhd",
        "ghdl_marker": "RADHDL_FIFO_SYNC_LATTICE_GHDL_OK",
        "xsim_marker": "RADHDL_FIFO_SYNC_XILINX_XPM_XSIM_OK",
    },
}


class SimError(RuntimeError):
    pass


def run(cmd: list[str], *, cwd: Path, env: dict[str, str] | None = None) -> subprocess.CompletedProcess:
    print("+ " + " ".join(shlex.quote(part) for part in cmd))
    proc = subprocess.run(cmd, cwd=cwd, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(proc.stdout, end="")
    if proc.returncode != 0:
        raise SimError(f"command failed with status {proc.returncode}: {' '.join(cmd)}")
    return proc


def run_bash(script: str, *, cwd: Path) -> subprocess.CompletedProcess:
    print("+ bash -lc " + shlex.quote(script))
    proc = subprocess.run(["bash", "-lc", script], cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(proc.stdout, end="")
    if proc.returncode != 0:
        raise SimError(f"bash command failed with status {proc.returncode}")
    return proc


def xilinx_versions(root: Path) -> list[dict[str, str]]:
    versions: list[dict[str, str]] = []
    for vcomp in sorted(root.glob("*/data/ip/xpm/xpm_VCOMP.vhd")):
        vivado_root = vcomp.parents[3]
        xpm_root = vcomp.parent
        files = {
            "version": vivado_root.name,
            "vivado_root": str(vivado_root),
            "xpm_root": str(xpm_root),
            "vcomp": str(vcomp),
            "memory_sv": str(xpm_root / "xpm_memory" / "hdl" / "xpm_memory.sv"),
            "fifo_sv": str(xpm_root / "xpm_fifo" / "hdl" / "xpm_fifo.sv"),
            "cdc_sv": str(xpm_root / "xpm_cdc" / "hdl" / "xpm_cdc.sv"),
        }
        if all(Path(files[key]).exists() for key in ("memory_sv", "fifo_sv", "cdc_sv")):
            versions.append(files)
    return versions


def choose_xilinx(version: str | None) -> dict[str, str]:
    versions = xilinx_versions(Path("/home/jvincent/xilinx/Vivado"))
    if not versions:
        raise SimError("no Vivado XPM source trees found under /home/jvincent/xilinx/Vivado")
    if version:
        for item in versions:
            if item["version"] == version:
                return item
        raise SimError(f"Vivado {version} was requested but was not found")
    for preferred in ("2024.1", "2023.1", "2021.1"):
        for item in versions:
            if item["version"] == preferred:
                return item
    return versions[-1]


def clean_build_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    for child in path.iterdir():
        if child.is_file() or child.is_symlink():
            child.unlink()


def run_ghdl_lattice(args: argparse.Namespace) -> dict[str, str]:
    build = args.build_dir / "generic-ghdl"
    clean_build_dir(build)
    ghdl = args.ghdl
    files = [ROOT / path for path in PRIMITIVE_VHDL]
    files.extend(ROOT / tb["file"] for tb in TESTBENCHES.values())
    for file_path in files:
        run([ghdl, "-a", "--std=08", str(file_path)], cwd=build)

    results: dict[str, str] = {}
    for name, tb in TESTBENCHES.items():
        top = tb["top"]
        marker = tb["ghdl_marker"]
        run([ghdl, "-e", "--std=08", top], cwd=build)
        proc = run(
            [
                ghdl,
                "-r",
                "--std=08",
                top,
                "-gVENDOR=lattice",
                "-gDEVICE_FAMILY=ecp5",
                f"-gDONE_MARKER={marker}",
                "--assert-level=error",
                "--stop-time=5us",
            ],
            cwd=build,
        )
        if marker not in proc.stdout:
            raise SimError(f"{name} did not report {marker}")
        results[name] = marker
    return results


def run_xsim_xpm(args: argparse.Namespace) -> dict[str, str]:
    xpm = choose_xilinx(args.vivado_version)
    build = args.build_dir / "xilinx-xsim"
    clean_build_dir(build)

    vhdl_files = [ROOT / path for path in XILINX_WRAPPER_VHDL]
    tb_files = [ROOT / tb["file"] for tb in TESTBENCHES.values()]
    settings = Path(xpm["vivado_root"]) / "settings64.sh"
    if not settings.exists():
        raise SimError(f"missing Vivado settings script: {settings}")

    def vivado_cmd(command: list[str]) -> None:
        quoted = " ".join(shlex.quote(part) for part in command)
        run_bash(f"source {shlex.quote(str(settings))} >/dev/null && {quoted}", cwd=build)

    vivado_cmd(["xvhdl", "--work", "xpm", xpm["vcomp"]])
    vivado_cmd(["xvlog", "-sv", "--work", "xpm", xpm["memory_sv"], xpm["fifo_sv"], xpm["cdc_sv"]])
    vivado_cmd(["xvhdl", "--work", "work", *[str(path) for path in vhdl_files], *[str(path) for path in tb_files]])

    results: dict[str, str] = {}
    for name, tb in TESTBENCHES.items():
        top = tb["top"]
        marker = tb["xsim_marker"]
        snapshot = f"{top}_{name.replace('-', '_')}_xpm"
        tclbatch = build / f"{snapshot}.tcl"
        tclbatch.write_text("run 5 us\nquit\n")
        vivado_cmd(
            [
                "xelab",
                "--debug",
                "typical",
                "--relax",
                "--mt",
                "4",
                "-L",
                "xpm",
                "-L",
                "work",
                "-generic_top",
                "VENDOR=xilinx",
                "-generic_top",
                "DEVICE_FAMILY=7series",
                "-generic_top",
                f"DONE_MARKER={marker}",
                "--snapshot",
                snapshot,
                f"work.{top}",
            ]
        )
        proc = run_bash(
            f"source {shlex.quote(str(settings))} >/dev/null && "
            f"xsim {shlex.quote(snapshot)} -tclbatch {shlex.quote(str(tclbatch))} "
            f"-log {shlex.quote(snapshot + '.log')}",
            cwd=build,
        )
        log_text = proc.stdout
        log_file = build / f"{snapshot}.log"
        if log_file.exists():
            log_text += log_file.read_text(errors="replace")
        if marker not in log_text:
            raise SimError(f"{name} did not report {marker}")
        results[name] = marker
    return results


def run_xpm_verilator_probe(args: argparse.Namespace) -> dict[str, object]:
    xpm = choose_xilinx(args.vivado_version)
    build = args.build_dir / "xilinx-verilator-probe"
    clean_build_dir(build)
    results: dict[str, object] = {"vivado_version": xpm["version"], "modules": {}}
    for label, path_key in (("memory", "memory_sv"), ("fifo", "fifo_sv"), ("cdc", "cdc_sv")):
        proc = subprocess.run(
            [args.verilator, "--lint-only", "-sv", xpm[path_key]],
            cwd=build,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        (build / f"{label}.verilator.log").write_text(proc.stdout)
        results["modules"][label] = {
            "status": "ok" if proc.returncode == 0 else "xsim-required",
            "returncode": proc.returncode,
            "log": str(build / f"{label}.verilator.log"),
        }
    return results


def write_summary(path: Path, data: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")
    print(f"Wrote {path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["detect-xpm", "generic-ghdl", "xilinx-xsim", "xpm-verilator-probe", "all"], default="all")
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD)
    parser.add_argument("--vivado-version", default=None)
    parser.add_argument("--ghdl", default=os.environ.get("GHDL", "/usr/bin/ghdl"))
    parser.add_argument("--verilator", default=os.environ.get("VERILATOR", "verilator"))
    args = parser.parse_args()

    args.build_dir = args.build_dir.resolve()
    args.build_dir.mkdir(parents=True, exist_ok=True)
    summary: dict[str, object] = {"root": str(ROOT), "build_dir": str(args.build_dir), "results": {}}

    try:
      if args.mode in ("detect-xpm", "all"):
          summary["xpm"] = xilinx_versions(Path("/home/jvincent/xilinx/Vivado"))
      if args.mode in ("generic-ghdl", "all"):
          summary["results"]["generic-ghdl"] = run_ghdl_lattice(args)
      if args.mode in ("xilinx-xsim", "all"):
          summary["results"]["xilinx-xsim"] = run_xsim_xpm(args)
      if args.mode in ("xpm-verilator-probe", "all"):
          summary["results"]["xpm-verilator-probe"] = run_xpm_verilator_probe(args)
      write_summary(args.build_dir / "summary.json", summary)
    except SimError as exc:
      summary["error"] = str(exc)
      write_summary(args.build_dir / "summary.json", summary)
      print(f"ERROR: {exc}", file=sys.stderr)
      return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
