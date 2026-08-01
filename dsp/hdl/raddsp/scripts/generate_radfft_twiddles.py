#!/usr/bin/env python3
import argparse
import math
from pathlib import Path


def twos_complement(value: int, width: int) -> int:
    mask = (1 << width) - 1
    return value & mask


def quantize(value: float, width: int) -> int:
    scale = 1 << (width - 2)
    limit_hi = (1 << (width - 1)) - 1
    limit_lo = -(1 << (width - 1))
    quantized = int(round(value * scale))
    return max(limit_lo, min(limit_hi, quantized))


def write_mem(path: Path, points: int, width: int) -> None:
    hex_digits = (2 * width + 3) // 4
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii") as f:
        for exponent in range(points):
            angle = -2.0 * math.pi * exponent / points
            re = quantize(math.cos(angle), width)
            im = quantize(math.sin(angle), width)
            packed = (twos_complement(re, width) << width) | twos_complement(im, width)
            f.write(f"{packed:0{hex_digits}X}\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate RADFFT packed twiddle ROM .mem files.")
    parser.add_argument("--points", type=int, required=True)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    if args.points <= 0 or args.points & (args.points - 1):
        raise SystemExit("--points must be a positive power of two")
    if args.width < 2 or args.width > 32:
        raise SystemExit("--width must be in the range 2..32")

    write_mem(args.output, args.points, args.width)


if __name__ == "__main__":
    main()
