#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def parse_int(value):
    if isinstance(value, int):
        return value
    return int(str(value), 0)


def flatten_registers(spec):
    width = int(spec.get("data_width", 32))
    registers = []
    logical_to_flat = {}
    for region in spec.get("regions", []):
        base = parse_int(region.get("base", 0))
        region_name = region["name"]
        for reg in region.get("registers", []):
            offset = parse_int(reg.get("offset", 0))
            flat_name = f"{region_name}.{reg['name']}"
            logical_to_flat[flat_name] = flat_name
            registers.append({
                "name": flat_name,
                "address": f"0x{base + offset:04X}",
                "region": region_name,
                "offset": f"0x{offset:04X}",
                "width": int(reg.get("width", width)),
                "access": reg.get("access", "rw"),
                "reset": reg.get("reset", 0),
                "description": reg.get("description", "")
            })
    return registers, logical_to_flat


def convert_regions(spec):
    regions = []
    for region in spec.get("regions", []):
        regions.append({
            "name": region["name"],
            "base": f"0x{parse_int(region.get('base', 0)):04X}",
            "mask": f"0x{parse_int(region.get('mask', 0)):04X}",
            "description": region.get("description", "")
        })
    return regions


def convert_accelerators(spec):
    out = []
    for accel in spec.get("dsp_accelerators", []):
        item = dict(accel)
        regs = {}
        for key, name in accel.get("registers", {}).items():
            regs[key] = name
        item["registers"] = regs
        out.append(item)
    return out


def write_radlib_json(spec, out_path):
    registers, _ = flatten_registers(spec)
    radlib = {
        "schema": "radfpga-map",
        "schema_version": int(spec.get("schema_version", 1)),
        "name": spec.get("name", "unnamed"),
        "version": spec.get("version", "0.0.0"),
        "description": spec.get("description", ""),
        "producer": {
            "name": "RadHDL",
            "tool": "projects/scripts/generate_address_maps.py"
        },
        "compatibility": spec.get("compatibility", {}),
        "data_width": int(spec.get("data_width", 32)),
        "address_width": int(spec.get("address_width", 16)),
        "transport": spec.get("transport", {"type": "custom"}),
        "regions": convert_regions(spec),
        "registers": registers,
        "dsp_accelerators": convert_accelerators(spec)
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(radlib, indent=2) + "\n")


def write_text_map(spec, out_path):
    registers, _ = flatten_registers(spec)
    lines = [
        f"name: {spec.get('name', 'unnamed')}",
        f"schema_version: {spec.get('schema_version', 1)}",
        f"version: {spec.get('version', '0.0.0')}",
        f"data_width: {spec.get('data_width', 32)}",
        f"address_width: {spec.get('address_width', 16)}",
        "",
        "regions:"
    ]
    for region in spec.get("regions", []):
        lines.append(f"  {region['name']}: base={region.get('base', '0x0')} mask={region.get('mask', '0x0')}")
    lines.extend(["", "registers:"])
    for reg in registers:
        desc = f" # {reg['description']}" if reg.get("description") else ""
        lines.append(f"  {reg['address']} {reg['access']:>2} {reg['width']:>2} {reg['name']}{desc}")
    lines.append("")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines))


def main():
    parser = argparse.ArgumentParser(description="Generate RADLib-readable FPGA maps from RadHDL project maps.")
    parser.add_argument("input", type=Path)
    parser.add_argument("--radlib-json", type=Path, required=True)
    parser.add_argument("--text", type=Path, required=True)
    args = parser.parse_args()

    spec = json.loads(args.input.read_text())
    write_radlib_json(spec, args.radlib_json)
    write_text_map(spec, args.text)


if __name__ == "__main__":
    main()
