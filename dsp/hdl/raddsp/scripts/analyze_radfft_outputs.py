#!/usr/bin/env python3
"""Compare RADFFT simulation CSVs against NumPy FFT references."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


CONFIGS = (
    ("batch_radix2_fft", "radfft_batch_radix2_fft.csv", "fft"),
    ("batch_radix4_fft", "radfft_batch_radix4_fft.csv", "fft"),
    ("stream_radix2_fft", "radfft_stream_radix2_fft.csv", "fft"),
    ("stream_radix4_ifft", "radfft_stream_radix4_ifft.csv", "ifft"),
)

XCORR_CONFIGS = (
    ("fft_cross_correlation", "radfft_xcorr_fft.csv"),
)


def read_complex_csv(path: Path) -> np.ndarray:
    with path.open(newline="") as f:
        rows = list(csv.DictReader(f))
    return np.array([int(row["re"]) + 1j * int(row["im"]) for row in rows], dtype=np.complex128)


def expected_fft(samples: np.ndarray, mode: str) -> np.ndarray:
    if mode == "fft":
        return np.fft.fft(samples) / len(samples)
    if mode == "ifft":
        return np.fft.ifft(samples)
    raise ValueError(f"unsupported mode: {mode}")


def expected_xcorr(a_samples: np.ndarray, b_samples: np.ndarray) -> np.ndarray:
    points = len(a_samples)
    a_fft_scaled = np.fft.fft(a_samples) / points
    b_fft_scaled = np.fft.fft(b_samples) / points
    return np.fft.ifft(a_fft_scaled * np.conj(b_fft_scaled))


def plot_result(name: str, actual: np.ndarray, expected: np.ndarray, output_dir: Path) -> None:
    x = np.arange(len(actual))
    error = actual - expected

    fig, axes = plt.subplots(3, 1, figsize=(10, 8), sharex=True)
    axes[0].plot(x, expected.real, "k--", label="expected re")
    axes[0].plot(x, actual.real, "tab:blue", marker="o", label="hdl re")
    axes[0].set_ylabel("real")
    axes[0].grid(True, alpha=0.3)
    axes[0].legend(loc="best")

    axes[1].plot(x, expected.imag, "k--", label="expected im")
    axes[1].plot(x, actual.imag, "tab:orange", marker="o", label="hdl im")
    axes[1].set_ylabel("imag")
    axes[1].grid(True, alpha=0.3)
    axes[1].legend(loc="best")

    axes[2].stem(x, np.abs(error), basefmt=" ")
    axes[2].set_ylabel("abs error")
    axes[2].set_xlabel("bin")
    axes[2].grid(True, alpha=0.3)

    fig.suptitle(name)
    fig.tight_layout()
    fig.savefig(output_dir / f"{name}.png", dpi=140)
    plt.close(fig)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "analysis_dir",
        nargs="?",
        default="dsp/hdl/raddsp/build/radfft_analysis",
        help="Directory containing RADFFT simulation CSV files.",
    )
    parser.add_argument("--tolerance", type=float, default=2.0, help="Maximum allowed absolute complex error.")
    args = parser.parse_args()

    analysis_dir = Path(args.analysis_dir)
    input_path = analysis_dir / "radfft_input.csv"
    input_samples = read_complex_csv(input_path) if input_path.exists() else None
    summary = {}
    failed = False

    for name, filename, mode in CONFIGS:
        if input_samples is None or not (analysis_dir / filename).exists():
            continue
        actual = read_complex_csv(analysis_dir / filename)
        expected = expected_fft(input_samples, mode)
        error = actual - expected
        max_abs = float(np.max(np.abs(error)))
        mean_abs = float(np.mean(np.abs(error)))
        summary[name] = {
            "mode": mode,
            "samples": int(len(actual)),
            "max_abs_error": max_abs,
            "mean_abs_error": mean_abs,
            "passed": max_abs <= args.tolerance,
        }
        failed = failed or max_abs > args.tolerance
        plot_result(name, actual, expected, analysis_dir)

    xcorr_a_path = analysis_dir / "radfft_xcorr_input_a.csv"
    xcorr_b_path = analysis_dir / "radfft_xcorr_input_b.csv"
    if xcorr_a_path.exists() and xcorr_b_path.exists():
        xcorr_a = read_complex_csv(xcorr_a_path)
        xcorr_b = read_complex_csv(xcorr_b_path)
        for name, filename in XCORR_CONFIGS:
            path = analysis_dir / filename
            if not path.exists():
                continue
            actual = read_complex_csv(path)
            expected = expected_xcorr(xcorr_a, xcorr_b)
            error = actual - expected
            max_abs = float(np.max(np.abs(error)))
            mean_abs = float(np.mean(np.abs(error)))
            summary[name] = {
                "mode": "fft_xcorr",
                "samples": int(len(actual)),
                "max_abs_error": max_abs,
                "mean_abs_error": mean_abs,
                "passed": max_abs <= args.tolerance,
            }
            failed = failed or max_abs > args.tolerance
            plot_result(name, actual, expected, analysis_dir)

    summary_path = analysis_dir / "radfft_analysis_summary.json"
    summary_path.write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
