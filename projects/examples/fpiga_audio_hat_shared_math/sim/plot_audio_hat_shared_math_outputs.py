#!/usr/bin/env python3
"""Generate quick-look PNG plots for the FPiGA audio hat top-level simulation."""

from __future__ import annotations

import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "build" / "sim" / "audio_hat_shared_math_top"
PLOT_DIR = OUT_DIR / "plots"


def load_s32le(path: Path) -> np.ndarray:
    if not path.exists() or path.stat().st_size == 0:
        return np.empty((0, 2), dtype=np.int32)
    raw = np.fromfile(path, dtype="<i4")
    if raw.size % 2:
        raw = raw[:-1]
    return raw.reshape((-1, 2))


def safe_name(name: str) -> str:
    return "".join(ch if ch.isalnum() or ch in ("-", "_") else "_" for ch in name)


def display_name(name: str) -> str:
    return name.replace("_", " ").title()


def plot_capture(name: str, description: str, data: np.ndarray, sample_rate: int, plot_frames: int) -> None:
    fig, axes = plt.subplots(3, 1, figsize=(12, 8), constrained_layout=True)
    fig.suptitle(display_name(name), fontsize=14, fontweight="bold")

    if data.size == 0:
        axes[0].text(0.5, 0.5, "No frames captured", ha="center", va="center", transform=axes[0].transAxes)
        axes[0].set_title(description, fontsize=10)
        axes[1].axis("off")
        axes[2].axis("off")
    else:
        n = min(len(data), plot_frames)
        t = np.arange(n) / sample_rate
        axes[0].plot(t, data[:n, 0], color="#1f77b4", linewidth=1.4)
        axes[0].set_title("Left Channel")
        axes[0].axhline(0, color="black", linewidth=0.8, alpha=0.35)
        axes[0].set_ylabel("Signed sample")
        axes[0].grid(True, alpha=0.25)

        axes[1].plot(t, data[:n, 1], color="#2ca02c", linewidth=1.4)
        axes[1].set_title("Right Channel")
        axes[1].set_xlabel("Time (s)")
        axes[1].axhline(0, color="black", linewidth=0.8, alpha=0.35)
        axes[1].set_ylabel("Signed sample")
        axes[1].grid(True, alpha=0.25)

        fft_len = min(len(data), 2048)
        if fft_len >= 4:
            x = data[:fft_len, 0].astype(np.float64)
            x -= x.mean()
            window = np.hanning(fft_len)
            spectrum = np.abs(np.fft.rfft(x * window))
            freqs = np.fft.rfftfreq(fft_len, d=1.0 / sample_rate)
            axes[2].plot(freqs, spectrum, color="#9467bd", linewidth=1.2)
            axes[2].set_xlim(0, min(sample_rate / 2, 6000))
            axes[2].set_title("Left Channel FFT Quick Look")
            axes[2].set_xlabel("Frequency (Hz)")
            axes[2].set_ylabel("Magnitude")
            axes[2].grid(True, alpha=0.25)
        else:
            axes[2].text(0.5, 0.5, "Not enough frames for FFT", ha="center", va="center", transform=axes[2].transAxes)
            axes[2].axis("off")

    fig.savefig(PLOT_DIR / f"{safe_name(name)}.png", dpi=150)
    plt.close(fig)


def main() -> None:
    manifest = json.loads((OUT_DIR / "manifest.json").read_text())
    sample_rate = int(manifest["format"]["sample_rate_hz"])
    run = manifest.get("run", {})
    capture_frames = int(run.get("capture_frames", 512))
    plot_frames = int(run.get("plot_frames", capture_frames))
    plot_frames = min(max(plot_frames, 1), max(capture_frames, 1), sample_rate // 10)
    PLOT_DIR.mkdir(parents=True, exist_ok=True)

    for scenario in manifest["scenarios"]:
        data = load_s32le(OUT_DIR / scenario["file"])
        plot_capture(scenario["name"], scenario["description"], data, sample_rate, plot_frames)

    print(f"Generated quick-look plots in {PLOT_DIR}")


if __name__ == "__main__":
    main()
