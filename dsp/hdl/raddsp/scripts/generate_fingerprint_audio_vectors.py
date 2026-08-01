#!/usr/bin/env python3
"""Generate deterministic audio-derived fingerprint vectors for HDL simulation."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np


HASH_WIDTH = 64
HASH_MASK = (1 << HASH_WIDTH) - 1
GOLDEN = 0x9E3779B9


def rol(value: int, count: int, width: int = HASH_WIDTH) -> int:
    count %= width
    return ((value << count) | (value >> (width - count))) & ((1 << width) - 1)


def hash_mix(old_hash: int, bin_idx: int, mag: int) -> int:
    word = ((bin_idx & 0xFFFF) << 16) | (mag & 0xFFFF)
    mixed = rol(old_hash, 5) ^ word ^ rol(word, 17)
    return (mixed + GOLDEN) & HASH_MASK


def fold_peak_hash(seed: int, bins: list[int], mags: list[int], tag: int) -> int:
    h = hash_mix(seed, tag, tag)
    for b, m in zip(bins, mags):
        h = hash_mix(h, b, m)
    return h


def make_clip(kind: int, sample_rate: int, seconds: float) -> np.ndarray:
    t = np.arange(int(sample_rate * seconds), dtype=np.float64) / sample_rate
    rng = np.random.default_rng(1000 + kind)
    if kind == 0:
        x = 0.70 * np.sin(2 * np.pi * 437.0 * t) + 0.25 * np.sin(2 * np.pi * 1220.0 * t)
    elif kind == 1:
        f0, f1 = 220.0, 1800.0
        phase = 2 * np.pi * (f0 * t + 0.5 * (f1 - f0) / seconds * t * t)
        x = 0.75 * np.sin(phase) + 0.18 * np.sin(2 * np.pi * 710.0 * t)
    elif kind == 2:
        x = 0.55 * np.sin(2 * np.pi * 331.0 * t)
        x += 0.35 * np.sin(2 * np.pi * 997.0 * t + 0.7 * np.sin(2 * np.pi * 2.0 * t))
    elif kind >= 100:
        base = kind - 100
        f0 = 145.0 + 37.0 * ((base * 3) % 43)
        f1 = 310.0 + 53.0 * ((base * 5 + 7) % 37)
        f2 = 620.0 + 71.0 * ((base * 11 + 3) % 31)
        mod = 1.0 + 0.15 * np.sin(2 * np.pi * (0.35 + 0.07 * (base % 9)) * t)
        chirp_span = 180.0 + 23.0 * (base % 13)
        phase = 2 * np.pi * (f0 * t + 0.5 * chirp_span / seconds * t * t)
        x = 0.42 * mod * np.sin(phase + 0.17 * base)
        x += 0.31 * np.sin(2 * np.pi * f1 * t + 0.03 * base)
        x += 0.19 * np.sin(2 * np.pi * f2 * t + 0.5 * np.sin(2 * np.pi * 1.3 * t))
        if base % 3 == 0:
            x += 0.13 * np.sign(np.sin(2 * np.pi * (780.0 + 19.0 * base) * t))
        if base % 5 == 0:
            pulse = ((np.arange(t.size) + 17 * base) % max(8, sample_rate // 80)) == 0
            x += 0.20 * pulse.astype(np.float64)
    else:
        x = 0.55 * np.sin(2 * np.pi * 523.25 * t)
        x += 0.30 * np.sin(2 * np.pi * 1666.0 * t)
        x += 0.08 * rng.standard_normal(t.shape)
    x += 0.015 * rng.standard_normal(t.shape)
    peak = np.max(np.abs(x))
    if peak > 0:
        x = x / peak * 0.90
    return x.astype(np.float64)


def fft_frames(samples: np.ndarray, frame_bins: int, fft_scale: int) -> list[np.ndarray]:
    usable = (len(samples) // frame_bins) * frame_bins
    samples = samples[:usable]
    window = np.hanning(frame_bins)
    frames: list[np.ndarray] = []
    for start in range(0, usable, frame_bins):
        spectrum = np.fft.fft(samples[start : start + frame_bins] * window)
        max_abs = np.max(np.abs(spectrum))
        scale = fft_scale / max_abs if max_abs > 0 else 1.0
        q_re = np.clip(np.rint(np.real(spectrum) * scale), -32768, 32767).astype(np.int32)
        q_im = np.clip(np.rint(np.imag(spectrum) * scale), -32768, 32767).astype(np.int32)
        frames.append(np.stack([q_re, q_im], axis=1))
    return frames


def top4_for_frame(frame: np.ndarray) -> tuple[list[int], list[int]]:
    bins = [0, 0, 0, 0]
    mags = [0, 0, 0, 0]
    for idx, (re, im) in enumerate(frame):
        mag = int(abs(int(re)) + abs(int(im)))
        if mag > mags[0]:
            mags = [mag, mags[0], mags[1], mags[2]]
            bins = [idx, bins[0], bins[1], bins[2]]
        elif mag > mags[1]:
            mags = [mags[0], mag, mags[1], mags[2]]
            bins = [bins[0], idx, bins[1], bins[2]]
        elif mag > mags[2]:
            mags = [mags[0], mags[1], mag, mags[2]]
            bins = [bins[0], bins[1], idx, bins[2]]
        elif mag > mags[3]:
            mags[3] = mag
            bins[3] = idx
    return bins, mags


def pair_fingerprints(frames: list[np.ndarray], seed: int, gap: int) -> list[dict[str, int]]:
    history: list[tuple[list[int], list[int]]] = []
    out: list[dict[str, int]] = []
    for frame_idx, frame in enumerate(frames):
        bins, mags = top4_for_frame(frame)
        if frame_idx > gap and len(history) > gap:
            prev_bins, prev_mags = history[gap]
            delta = gap + 1
            h = fold_peak_hash(seed, prev_bins, prev_mags, 1)
            h = fold_peak_hash(h, bins, mags, 2)
            h = hash_mix(h, delta, delta)
            out.append(
                {
                    "hash": h,
                    "frame": frame_idx,
                    "delta": delta,
                    "a_peak": prev_bins[0],
                    "b_peak": bins[0],
                }
            )
        history.insert(0, (bins, mags))
        history = history[:16]
    return out


def write_bins(path: Path, frames: list[np.ndarray]) -> None:
    with path.open("w", encoding="ascii") as f:
        f.write(f"{len(frames)} {len(frames[0])}\n")
        for frame in frames:
            for idx, (re, im) in enumerate(frame):
                last = 1 if idx == len(frame) - 1 else 0
                f.write(f"{int(re)} {int(im)} {last}\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", default="dsp/hdl/raddsp/build/fingerprint_audio_tb/vectors")
    parser.add_argument("--sample-rate", type=int, default=8000)
    parser.add_argument("--seconds", type=float, default=2.0)
    parser.add_argument("--frame-bins", type=int, default=256)
    parser.add_argument("--fft-scale", type=int, default=12000)
    parser.add_argument("--table-addr-width", type=int, default=10)
    parser.add_argument("--pair-gap", type=int, default=0)
    parser.add_argument("--impostors", type=int, default=32)
    parser.add_argument("--seed", type=lambda x: int(x, 0), default=0x123456789ABCDEF0)
    args = parser.parse_args()

    if args.pair_gap < 0 or args.pair_gap > 15:
        raise SystemExit("pair gap must be between 0 and 15")
    if args.impostors < 1:
        raise SystemExit("impostors must be at least 1")

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    enrolled_clips = [make_clip(i, args.sample_rate, args.seconds) for i in range(3)]
    match_clip = make_clip(1, args.sample_rate, args.seconds)
    impostor_clips = [make_clip(100 + i, args.sample_rate, args.seconds) for i in range(args.impostors)]

    enrolled_frames = [fft_frames(c, args.frame_bins, args.fft_scale) for c in enrolled_clips]
    match_frames_data = fft_frames(match_clip, args.frame_bins, args.fft_scale)
    impostor_frames_data = [fft_frames(c, args.frame_bins, args.fft_scale) for c in impostor_clips]

    enrolled_fps = [pair_fingerprints(fr, args.seed, args.pair_gap) for fr in enrolled_frames]
    match_fps = pair_fingerprints(match_frames_data, args.seed, args.pair_gap)
    impostor_fps = [pair_fingerprints(fr, args.seed, args.pair_gap) for fr in impostor_frames_data]

    table_depth = 1 << args.table_addr_width
    table: dict[int, tuple[int, int]] = {}
    for track_id in range(3):
        for fp in enrolled_fps[track_id]:
            bucket = fp["hash"] & (table_depth - 1)
            meta = ((track_id & 0xFFFF) << 16) | (fp["frame"] & 0xFFFF)
            if bucket not in table:
                table[bucket] = (fp["hash"], meta)

    def expected_for(fingerprints: list[dict[str, int]]) -> int:
        count = 0
        for fp in fingerprints:
            bucket = fp["hash"] & (table_depth - 1)
            entry = table.get(bucket)
            if entry is not None and entry[0] == fp["hash"]:
                count += 1
        return count

    expected_match = expected_for(match_fps)
    impostor_expected = [expected_for(fp) for fp in impostor_fps]
    expected_impostor_total = sum(impostor_expected)
    if expected_match <= 0:
        raise SystemExit("generated table produced no expected positive matches")

    with (out_dir / "config.txt").open("w", encoding="ascii") as f:
        f.write(
            f"{args.frame_bins} {args.table_addr_width} {args.pair_gap} "
            f"{len(table)} {len(match_frames_data)} {len(impostor_frames_data[0])} "
            f"{expected_match} {expected_impostor_total} {args.impostors}\n"
        )
        f.write(f"{args.seed >> 32:08X} {args.seed & 0xFFFFFFFF:08X}\n")
        for expected in impostor_expected:
            f.write(f"{expected}\n")

    with (out_dir / "table.txt").open("w", encoding="ascii") as f:
        for bucket, (h, meta) in sorted(table.items()):
            f.write(f"{bucket} {h >> 32:08X} {h & 0xFFFFFFFF:08X} {meta:08X}\n")

    write_bins(out_dir / "query_match_bins.txt", match_frames_data)
    for i, frames in enumerate(impostor_frames_data):
        write_bins(out_dir / f"query_impostor_{i}_bins.txt", frames)

    with (out_dir / "summary.txt").open("w", encoding="ascii") as f:
        f.write(
            f"enrolled_clips=3 impostors={args.impostors} "
            f"sample_rate={args.sample_rate} seconds={args.seconds}\n"
        )
        f.write(
            f"frame_bins={args.frame_bins} frames_per_clip={len(enrolled_frames[0])} "
            f"pair_gap={args.pair_gap}\n"
        )
        f.write(f"table_entries={len(table)} table_depth={table_depth}\n")
        f.write(
            f"expected_match={expected_match} "
            f"expected_impostor_total={expected_impostor_total}\n"
        )
        f.write("impostor_expected=" + " ".join(str(v) for v in impostor_expected) + "\n")


if __name__ == "__main__":
    main()
