#!/usr/bin/env python3
"""Generate datasheet-style static HTML documentation for RadHDL."""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass, field
import html
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any


VERSION = "0.1.0"
HDL_SUFFIXES = {".vhd", ".vhdl"}
REGISTER_SUFFIXES = {".map.json", ".radlib.json"}
HDL_LIBRARY_DIRS = {
    "raddsp": ("dsp/hdl/raddsp/src",),
    "radif": ("interfaces/hdl/radif/src",),
    "radila": ("debug/radila/hdl/radila",),
}
HDL_SIM_MODEL_DIRS = {
    "xpm": ("sim/xpm",),
    "raddsp": ("dsp/hdl/raddsp/sim",),
    "radif": ("interfaces/hdl/radif/sim",),
}
VENDOR_SIM_LIBRARIES = {"unisim", "unimacro", "unisims_ver"}
GHDL_BASE_ARGS = ["--std=08", "--ieee=synopsys"]
EXCLUDED_PARTS = {
    ".git",
    ".Xil",
    ".srcs",
    "__pycache__",
    "build",
    "dist",
    "iprepo",
    "release",
    "sim",
    "xci",
    "xsim.dir",
    "ip_user_files",
    ".ip_user_files",
    "software",
}
ENTITY_RE = re.compile(r"^\s*entity\s+([A-Za-z][A-Za-z0-9_]*)\s+is\b", re.IGNORECASE | re.MULTILINE)
PACKAGE_RE = re.compile(r"^\s*package\s+(?!body\b)([A-Za-z][A-Za-z0-9_]*)\s+is\b", re.IGNORECASE | re.MULTILINE)
END_ENTITY_RE = re.compile(r"^\s*end(?:\s+entity)?(?:\s+[A-Za-z][A-Za-z0-9_]*)?\s*;", re.IGNORECASE | re.MULTILINE)
DECL_RE = re.compile(r"^\s*([A-Za-z][A-Za-z0-9_,\s]*)\s*:\s*(.+?)\s*;?\s*$", re.DOTALL)
PORT_RE = re.compile(r"^(inout|in|out|buffer)\s+(.+)$", re.IGNORECASE | re.DOTALL)
BIT_FIELD_RE = re.compile(
    r"\bbits?\s*(?:\[?\s*(\d+)\s*(?::|downto|-)\s*(\d+)\s*\]?|(\d+))\s*[:=-]?\s*([^,;.]+)",
    re.IGNORECASE,
)
VHDL_REG_CONSTANT_RE = re.compile(
    r"\bconstant\s+C_REG_([A-Za-z0-9_]+)\s*:\s*(?:natural|integer)\s*:=\s*16#([0-9A-Fa-f_]+)#\s*;",
    re.IGNORECASE,
)


@dataclass
class FieldDoc:
    name: str
    direction: str = ""
    data_type: str = ""
    default: str = ""
    description: str = ""


@dataclass
class TestbenchDoc:
    name: str
    path: str
    description: str = ""
    related_modules: list[str] = field(default_factory=list)
    simulation: dict[str, Any] = field(default_factory=dict)


@dataclass
class RegisterDoc:
    name: str
    offset: str
    access: str = ""
    address: str = ""
    reset: str = ""
    width: int = 32
    region: str = ""
    description: str = ""
    fields: list[dict[str, Any]] = field(default_factory=list)


@dataclass
class RegisterMapDoc:
    name: str
    path: str
    base: str = ""
    description: str = ""
    data_width: int = 32
    registers: list[RegisterDoc] = field(default_factory=list)


@dataclass
class ModuleDoc:
    name: str
    kind: str
    path: str
    library: str
    category: str
    description: str = ""
    generics: list[FieldDoc] = field(default_factory=list)
    ports: list[FieldDoc] = field(default_factory=list)
    sources: list[str] = field(default_factory=list)
    testbenches: list[TestbenchDoc] = field(default_factory=list)
    register_maps: list[RegisterMapDoc] = field(default_factory=list)


@dataclass
class DiagramPort:
    name: str
    direction: str
    kind: str = "signal"
    members: list[FieldDoc] = field(default_factory=list)


def rel_path(path: Path, root: Path) -> str:
    return str(path.resolve().relative_to(root.resolve()))


def should_skip(path: Path, root: Path) -> bool:
    try:
        rel = path.resolve().relative_to(root.resolve())
    except ValueError:
        return True
    if any(part in EXCLUDED_PARTS for part in rel.parts):
        return True
    if any(part.endswith((".runs", ".gen", ".cache", ".hw", ".sim")) for part in rel.parts):
        return True
    return False


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(encoding="latin-1")


def clean_comment(line: str) -> str:
    return re.sub(r"^\s*--\s?", "", line).rstrip()


def comment_block_before(lines: list[str], index: int) -> str:
    comments: list[str] = []
    cursor = index - 1
    while cursor >= 0:
        line = lines[cursor]
        if line.strip().startswith("--"):
            comments.append(clean_comment(line))
            cursor -= 1
            continue
        if not line.strip() and comments:
            cursor -= 1
            continue
        break
    comments.reverse()
    return "\n".join(item for item in comments if item).strip()


def strip_inline_comment(line: str) -> str:
    return line.split("--", 1)[0].rstrip()


def category_for(path: Path, root: Path) -> str:
    parts = rel_path(path, root).split(os.sep)
    if "dsp" in parts:
        return "DSP"
    if "interfaces" in parts:
        return "Interfaces"
    if "debug" in parts:
        return "Debug"
    if "projects" in parts:
        return "Projects"
    return "Core"


def library_for(path: Path, root: Path) -> str:
    parts = rel_path(path, root).split(os.sep)
    if any(candidate in parts for candidate in ("raddsp", "radif", "radila")):
        return "radhdl"
    if parts:
        return parts[0]
    return "radhdl"


def find_matching_paren(text: str, open_index: int) -> int:
    depth = 0
    in_string = False
    cursor = open_index
    while cursor < len(text):
        char = text[cursor]
        if char == '"':
            in_string = not in_string
        elif not in_string:
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    return cursor
        cursor += 1
    return -1


def extract_block(body: str, keyword: str) -> str:
    match = re.search(rf"\b{keyword}\s*\(", body, re.IGNORECASE)
    if not match:
        return ""
    open_index = body.find("(", match.start())
    close_index = find_matching_paren(body, open_index)
    if close_index < 0:
        return ""
    return body[open_index + 1 : close_index]


def split_default(data_type: str) -> tuple[str, str]:
    if ":=" not in data_type:
        return data_type.strip(), ""
    left, right = data_type.split(":=", 1)
    return left.strip(), right.strip().rstrip(";")


def parse_fields(block: str, is_port: bool) -> list[FieldDoc]:
    fields: list[FieldDoc] = []
    pending_comments: list[str] = []
    statement = ""
    statement_comments: list[str] = []
    for raw in block.splitlines():
        if raw.strip().startswith("--"):
            pending_comments.append(clean_comment(raw))
            continue
        line = strip_inline_comment(raw)
        if not line.strip():
            continue
        if not statement:
            statement_comments = pending_comments
            pending_comments = []
        statement = f"{statement} {line.strip()}".strip()
        if ";" not in line and raw.strip()[-1:] != ")":
            continue
        statement = statement.rstrip(";").rstrip(",").strip()
        match = DECL_RE.match(statement)
        if match:
            names = [name.strip() for name in match.group(1).split(",") if name.strip()]
            tail = match.group(2).strip()
            description = " ".join(item.strip() for item in statement_comments if item.strip())
            if is_port:
                port_match = PORT_RE.match(tail)
                direction = port_match.group(1).lower() if port_match else ""
                data_type = port_match.group(2).strip() if port_match else tail
                for name in names:
                    fields.append(FieldDoc(name=name, direction=direction, data_type=data_type, description=description))
            else:
                data_type, default = split_default(tail)
                for name in names:
                    fields.append(FieldDoc(name=name, data_type=data_type, default=default, description=description))
        statement = ""
        statement_comments = []
    return fields


def parse_vhdl_file(path: Path, root: Path) -> list[ModuleDoc]:
    text = read_text(path)
    lines = text.splitlines()
    modules: list[ModuleDoc] = []
    for index, line in enumerate(lines):
        entity_match = ENTITY_RE.match(line)
        package_match = PACKAGE_RE.match(line)
        if not entity_match and not package_match:
            continue
        name = (entity_match or package_match).group(1)
        kind = "entity" if entity_match else "package"
        if kind == "entity" and name.lower().startswith("tb_"):
            continue
        body_start = sum(len(item) + 1 for item in lines[:index])
        end_index = len(text)
        if kind == "entity":
            for end_line in range(index + 1, len(lines)):
                if END_ENTITY_RE.match(lines[end_line]):
                    end_index = sum(len(item) + 1 for item in lines[: end_line + 1])
                    break
        body = text[body_start:end_index]
        generics = parse_fields(extract_block(body, "generic"), is_port=False)
        ports = parse_fields(extract_block(body, "port"), is_port=True)
        modules.append(
            ModuleDoc(
                name=name,
                kind=kind,
                path=rel_path(path, root),
                library=library_for(path, root),
                category=category_for(path, root),
                description=comment_block_before(lines, index),
                generics=generics,
                ports=ports,
                sources=[rel_path(path, root)],
            )
        )
    return modules


def discover_modules(root: Path) -> list[ModuleDoc]:
    modules: list[ModuleDoc] = []
    for path in sorted(root.rglob("*")):
        if should_skip(path, root) or path.suffix.lower() not in HDL_SUFFIXES or not path.is_file():
            continue
        modules.extend(parse_vhdl_file(path, root))
    return modules


def discover_testbenches(root: Path) -> list[TestbenchDoc]:
    benches: list[TestbenchDoc] = []
    for path in sorted(root.rglob("*")):
        if should_skip(path, root) or path.suffix.lower() not in HDL_SUFFIXES or not path.is_file():
            continue
        rel = rel_path(path, root)
        text = read_text(path)
        lines = text.splitlines()
        for match in ENTITY_RE.finditer(text):
            name = match.group(1)
            if name.lower().startswith("tb_") or "testbench" in rel.lower() or "testbenches" in rel.lower():
                line_index = text[: match.start()].count("\n")
                description = comment_block_before(lines, line_index)
                benches.append(TestbenchDoc(name=name, path=rel, description=description))
    return benches


def associate_testbenches(modules: list[ModuleDoc], benches: list[TestbenchDoc], root: Path) -> None:
    modules_by_name: dict[str, list[ModuleDoc]] = {}
    for module in modules:
        modules_by_name.setdefault(module.name.lower(), []).append(module)
    for bench in benches:
        text = read_text(root / bench.path).lower()
        matched: set[str] = set()
        for module in modules:
            name = module.name.lower()
            if name in text or name.replace("rad", "tb_rad", 1) in bench.name.lower():
                matched.add(module.name)
        suffix = bench.name.lower().removeprefix("tb_")
        if suffix in modules_by_name:
            matched.update(module.name for module in modules_by_name[suffix])
        bench.related_modules = sorted(matched)
        for name in bench.related_modules:
            for module in modules_by_name.get(name.lower(), []):
                module.testbenches.append(bench)


def hex_string(value: Any) -> str:
    if isinstance(value, int):
        return f"0x{value:X}"
    if value is None:
        return ""
    return str(value)


def int_value(value: Any) -> int | None:
    if isinstance(value, int):
        return value
    if value in (None, ""):
        return None
    try:
        return int(str(value), 0)
    except ValueError:
        return None


def parse_bit_fields(description: str) -> list[dict[str, Any]]:
    fields: list[dict[str, Any]] = []
    for match in BIT_FIELD_RE.finditer(description or ""):
        if match.group(3) is not None:
            msb = lsb = int(match.group(3))
        else:
            msb = int(match.group(1))
            lsb = int(match.group(2))
        if lsb > msb:
            msb, lsb = lsb, msb
        name = match.group(4).strip()
        fields.append({"name": name, "display_name": field_display_name(name), "description": field_description(name), "msb": msb, "lsb": lsb})
    return fields


def parse_bits(bits: Any) -> tuple[int, int] | None:
    text = str(bits or "").strip()
    if not text:
        return None
    match = re.fullmatch(r"\[?\s*(\d+)\s*(?::|downto|-)\s*(\d+)\s*\]?", text, re.IGNORECASE)
    if match:
        msb = int(match.group(1))
        lsb = int(match.group(2))
        if lsb > msb:
            msb, lsb = lsb, msb
        return msb, lsb
    match = re.fullmatch(r"\[?\s*(\d+)\s*\]?", text)
    if match:
        bit = int(match.group(1))
        return bit, bit
    return None


def explicit_register_fields(register: dict[str, Any]) -> list[dict[str, Any]]:
    fields: list[dict[str, Any]] = []
    for field in register.get("fields", []) or []:
        if not isinstance(field, dict):
            continue
        bit_range = parse_bits(field.get("bits"))
        if bit_range is None:
            continue
        name = str(field.get("name") or "").strip()
        if not name:
            continue
        display_name = str(field.get("display_name") or field_display_name(name))
        description = str(field.get("description") or field_description(name))
        fields.append(
            {
                "name": name,
                "display_name": display_name,
                "description": description,
                "msb": bit_range[0],
                "lsb": bit_range[1],
            }
        )
    return fields


def field_display_name(name: str) -> str:
    words = re.sub(r"[_-]+", " ", name).upper().split()
    replacements = {
        "ENABLE": "EN",
        "ENABLED": "EN",
        "CIRCULAR": "CIRC",
        "COMMAND": "CMD",
        "CONFIGURATION": "CFG",
        "INTERRUPT": "IRQ",
        "RESERVED": "RSVD",
        "STATUS": "STAT",
    }
    return " ".join(replacements.get(word, word) for word in words)


def field_description(name: str) -> str:
    clean = re.sub(r"[_-]+", " ", name).strip()
    upper = clean.upper()
    if "MM2S" in upper and "ENABLE" in upper:
        return "Enables MM2S transfer(s)."
    if "S2MM" in upper and "ENABLE" in upper:
        return "Enables S2MM transfer(s)."
    if "MM2S" in upper and "CIRC" in upper:
        return "Enables MM2S circular address wrapping."
    if "S2MM" in upper and "CIRC" in upper:
        return "Enables S2MM circular address wrapping."
    if "START" in upper:
        return "Starts the selected operation."
    if "DONE" in upper:
        return "Indicates that the selected operation completed."
    if "BUSY" in upper:
        return "Indicates that the block is actively processing."
    if "ERROR" in upper:
        return "Indicates that the block detected an error condition."
    if "CLEAR" in upper:
        return "Clears the associated sticky status flag(s)."
    if "IRQ" in upper or "INTERRUPT" in upper:
        return "Enables interrupt generation for the associated event."
    if "MODE" in upper:
        return "Selects the operating mode."
    return clean[:1].upper() + clean[1:] + "."


def access_description(access: str) -> str:
    normalized = access.lower()
    if normalized in {"ro", "read-only", "read_only"}:
        return "Read-only status or measurement"
    if normalized in {"wo", "write-only", "write_only"}:
        return "Write-only command"
    if normalized in {"rw", "read-write", "read_write"}:
        return "Read/write control or configuration"
    return "Memory-mapped"


def describe_register(register: dict[str, Any], region_name: str) -> str:
    explicit = str(register.get("description", "") or "").strip()
    raw_name = str(register.get("name", "register")).split(".")[-1]
    friendly = raw_name.replace("_", " ").strip()
    lower = raw_name.lower()
    if explicit:
        if parse_bit_fields(explicit) and any(token in lower for token in ("control", "ctrl", "cfg", "config")):
            return "Control register used to configure and control this block."
        return explicit
    if "scratch" in lower:
        return "Software scratch register reserved for driver diagnostics and register-path validation."
    if lower == "magic":
        return "Read-only identification value used by software to confirm that the expected register block is present."
    if lower == "version":
        return "Read-only hardware/register-map version value used for software compatibility checks."
    if "status" in lower:
        return "Read-only status register exposing current hardware state and latched conditions."
    if "clear" in lower:
        return "Write-one-to-clear command register for latched status or interrupt bits."
    if "counter" in lower or "count" in lower:
        return f"{access_description(str(register.get('access', '')))} counter register for the {region_name} region."
    if any(token in lower for token in ("base", "end", "addr", "address")):
        return f"{access_description(str(register.get('access', '')))} address register for the {region_name} region."
    if "length" in lower or "bytes" in lower:
        return f"{access_description(str(register.get('access', '')))} transfer length register for the {region_name} region."
    return f"{access_description(str(register.get('access', '')))} register for {friendly} in the {region_name} region."


def register_from_json(register: dict[str, Any], region_name: str, region_base: Any, default_width: int) -> RegisterDoc:
    description = describe_register(register, region_name)
    field_source = str(register.get("description", "") or description)
    width_value = register.get("width", default_width)
    try:
        width = int(width_value)
    except (TypeError, ValueError):
        width = default_width
    address = hex_string(register.get("address", ""))
    if not address:
        base_int = int_value(region_base)
        offset_int = int_value(register.get("offset", ""))
        if base_int is not None and offset_int is not None:
            address = f"0x{base_int + offset_int:04X}"
    return RegisterDoc(
        name=str(register.get("name", "")),
        offset=hex_string(register.get("offset", "")),
        access=str(register.get("access", "")),
        address=address,
        reset=hex_string(register.get("reset", "")),
        width=width,
        region=region_name,
        description=description,
        fields=explicit_register_fields(register) or parse_bit_fields(field_source),
    )


def load_register_maps(root: Path) -> list[RegisterMapDoc]:
    maps: list[RegisterMapDoc] = []
    map_stems = {path.name.removesuffix(".map.json") for path in root.rglob("*.map.json") if not should_skip(path, root)}
    for path in sorted(root.rglob("*.json")):
        if should_skip(path, root):
            continue
        name = path.name
        if not any(name.endswith(suffix) for suffix in REGISTER_SUFFIXES):
            continue
        if name.endswith(".radlib.json") and path.name.removesuffix(".radlib.json") in map_stems and "generated" in path.relative_to(root).parts:
            continue
        try:
            data = json.loads(read_text(path))
        except json.JSONDecodeError:
            continue
        regions = data.get("regions") if isinstance(data, dict) else None
        if not isinstance(regions, list):
            continue
        default_width = int(data.get("data_width", 32) or 32)
        flat_registers: dict[str, list[dict[str, Any]]] = {}
        for register in data.get("registers", []) or []:
            if isinstance(register, dict):
                flat_registers.setdefault(str(register.get("region", "")), []).append(register)
        maps_by_region: dict[str, RegisterMapDoc] = {}
        for region in regions:
            if not isinstance(region, dict):
                continue
            region_name = str(region.get("name") or data.get("name") or path.stem)
            registers: list[RegisterDoc] = []
            region_registers = region.get("registers", []) or flat_registers.get(region_name, [])
            for register in region_registers:
                if not isinstance(register, dict):
                    continue
                registers.append(register_from_json(register, region_name, region.get("base", ""), default_width))
            regmap = RegisterMapDoc(
                name=region_name,
                path=rel_path(path, root),
                base=hex_string(region.get("base", "")),
                description=str(region.get("description") or data.get("description") or ""),
                data_width=default_width,
                registers=registers,
            )
            maps.append(regmap)
            maps_by_region[region_name] = regmap
        for accelerator in data.get("dsp_accelerators", []) or []:
            if not isinstance(accelerator, dict) or not accelerator.get("block"):
                continue
            register_refs = accelerator.get("registers")
            if not isinstance(register_refs, dict):
                continue
            selected: list[RegisterDoc] = []
            selected_regions: list[RegisterMapDoc] = []
            for ref in register_refs.values():
                if not isinstance(ref, str) or "." not in ref:
                    continue
                region_name, register_name = ref.split(".", 1)
                source_map = maps_by_region.get(region_name)
                if not source_map:
                    continue
                if source_map not in selected_regions:
                    selected_regions.append(source_map)
                for register in source_map.registers:
                    if register.name == register_name and register not in selected:
                        selected.append(register)
                        break
            if not selected:
                continue
            base = selected_regions[0].base if len(selected_regions) == 1 else ""
            maps.append(
                RegisterMapDoc(
                    name=str(accelerator["block"]),
                    path=rel_path(path, root),
                    base=base,
                    description=(
                        f"Register subset used by accelerator {accelerator.get('name', accelerator['block'])} "
                        f"({accelerator.get('type', 'unspecified type')}) in {data.get('name', path.stem)}."
                    ),
                    data_width=default_width,
                    registers=selected,
                )
            )
    return maps


def inferred_register_description(name: str) -> str:
    lower = name.lower()
    if lower in {"ctrl", "control", "command", "cmd"}:
        return "Control register used to configure and control this block."
    if "status" in lower:
        return "Status register exposing current hardware state and latched conditions."
    if any(token in lower for token in ("addr", "address", "ptr", "index")):
        return "Address or index register used by the software-visible control interface."
    if any(token in lower for token in ("hash", "seed", "mask", "value", "meta", "selected")):
        return "Data or comparison value register used by the software-visible control interface."
    if any(token in lower for token in ("count", "bins", "size", "stride", "gap", "delta", "shift")):
        return "Configuration or measurement register used by the software-visible control interface."
    return "Register inferred from the module's VHDL register constant declarations."


def infer_vhdl_register_map(module: ModuleDoc, root: Path) -> RegisterMapDoc | None:
    registers: list[RegisterDoc] = []
    seen_offsets: set[str] = set()
    for source in module.sources:
        path = root / source
        if not path.exists():
            continue
        for match in VHDL_REG_CONSTANT_RE.finditer(read_text(path)):
            raw_name, raw_offset = match.groups()
            offset = f"0x{int(raw_offset.replace('_', ''), 16):02X}"
            if offset in seen_offsets:
                continue
            seen_offsets.add(offset)
            name = raw_name.lower()
            registers.append(
                RegisterDoc(
                    name=name,
                    offset=offset,
                    access="rw",
                    width=32,
                    description=inferred_register_description(name),
                )
            )
    if not registers:
        return None
    registers.sort(key=lambda item: int(item.offset, 16))
    return RegisterMapDoc(
        name=f"{module.name}_inferred",
        path=module.path,
        description=(
            "Register map inferred from C_REG_* constants in the VHDL source. "
            "Use this as a software-visible register index until a hand-authored map adds per-bit access details."
        ),
        data_width=32,
        registers=registers,
    )


def attach_inferred_register_maps(modules: list[ModuleDoc], root: Path) -> list[RegisterMapDoc]:
    inferred: list[RegisterMapDoc] = []
    for module in modules:
        if module.register_maps:
            continue
        regmap = infer_vhdl_register_map(module, root)
        if regmap:
            module.register_maps.append(regmap)
            inferred.append(regmap)
    return inferred


def attach_register_maps(modules: list[ModuleDoc], maps: list[RegisterMapDoc]) -> None:
    by_name = {module.name.lower(): module for module in modules}
    for regmap in maps:
        path_name = Path(regmap.path).name.lower()
        path_stem = path_name.removesuffix(".map.json").removesuffix(".radlib.json")
        exact_names = {regmap.name.lower(), path_stem}
        attached = False
        for name, module in by_name.items():
            if name in exact_names:
                module.register_maps.append(regmap)
                attached = True
        if not attached:
            for module in modules:
                if module.category == "Projects" and "projects/" in regmap.path:
                    module.register_maps.append(regmap)
                    break


def catalog(root: Path) -> tuple[list[ModuleDoc], list[TestbenchDoc], list[RegisterMapDoc]]:
    modules = discover_modules(root)
    benches = discover_testbenches(root)
    maps = load_register_maps(root)
    associate_testbenches(modules, benches, root)
    attach_register_maps(modules, maps)
    maps.extend(attach_inferred_register_maps(modules, root))
    return modules, benches, maps


def datasheet_modules(modules: list[ModuleDoc]) -> list[ModuleDoc]:
    return [module for module in modules if module.kind == "entity" and module.category != "Projects"]


def json_catalog(root: Path) -> dict[str, Any]:
    modules, benches, maps = catalog(root)
    return {
        "schema": "radhdl-docgen-catalog",
        "version": VERSION,
        "radhdl": str(root),
        "modules": [asdict(module) for module in modules],
        "testbenches": [asdict(bench) for bench in benches],
        "register_maps": [asdict(regmap) for regmap in maps],
    }


def module_slug(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", name)


def source_package_group(module: ModuleDoc) -> str:
    parts = module.path.split("/")
    if "iprepo" in parts:
        index = parts.index("iprepo")
        if index + 1 < len(parts):
            return parts[index + 1]
    for marker in ("raddsp", "radif", "radila"):
        if marker in parts:
            return marker
    return module.library


def dsp_package_group(module: ModuleDoc) -> str:
    name = module.name.lower()
    path = module.path.lower()
    haystack = f"{name} {path}"
    if any(token in haystack for token in ("matrix", "dot")):
        return "Matrix"
    if any(token in haystack for token in ("fir", "biquad", "lowpass", "filter", "equalizer", "eq_")):
        return "Filter"
    if any(token in haystack for token in ("fingerprint", "chirp", "correlator", "peak", "frame_stats", "zc_")):
        return "Detection"
    if any(token in haystack for token in ("fft", "cordic", "dds", "gain", "mix", "magnitude", "fixed_to_float", "float_to_fixed")):
        return "Transform"
    return "Misc"


def interface_include_package(module: ModuleDoc) -> str:
    name = module.name.lower()
    if "i2s" in name:
        return "interfaces_i2s"
    if "i2c" in name:
        return "interfaces_i2c"
    if "smi" in name:
        return "interfaces_smi"
    if "spi" in name or "qspi" in name:
        return "interfaces_spi"
    if "reg_bank" in name or "reg_interconnect" in name:
        return "interfaces_regbank"
    if "axi" in name or "axis" in name:
        return "interfaces_axi"
    return "interfaces"


def package_group(module: ModuleDoc) -> str:
    if module.category == "DSP":
        return dsp_package_group(module)
    return source_package_group(module)


def module_doc_slug(module: ModuleDoc) -> str:
    return module_slug(f"{package_group(module)}__{source_package_group(module)}__{module.name}")


def register_count(module: ModuleDoc) -> int:
    return sum(len(regmap.registers) for regmap in module.register_maps)


def register_search_text(module: ModuleDoc) -> str:
    parts: list[str] = []
    for regmap in module.register_maps:
        parts.extend([regmap.name, regmap.description, regmap.path])
        for register in regmap.registers:
            parts.extend([register.name, register.description, register.offset, register.access, register.reset])
            for field in register.fields:
                parts.extend(
                    [
                        str(field.get("name", "")),
                        str(field.get("description", "")),
                        str(field.get("bits", "")),
                        str(field.get("lsb", "")),
                        str(field.get("msb", "")),
                    ]
                )
    return " ".join(part for part in parts if part).lower()


def render_module_quick_links(module: ModuleDoc) -> str:
    links: list[str] = []
    if register_interface_groups(module):
        links.append('<a class="pill" href="#register-interfaces">Register interfaces</a>')
    regs = register_count(module)
    if regs:
        map_names = ", ".join(regmap.name for regmap in module.register_maps)
        label = f"Register maps: {map_names} ({regs} registers)"
        links.append(f'<a class="pill" href="#register-maps">{html.escape(label)}</a>')
    if module.testbenches:
        links.append(f'<a class="pill" href="#testbenches">Testbenches: {len(module.testbenches)}</a>')
    if not links:
        return ""
    return f'<div class="quick-links">{"".join(links)}</div>'


def docs_version(out: Path) -> str:
    return out.name or "current"


def write_css(out: Path, theme: str = "dark") -> None:
    if theme == "light":
        theme_vars = ":root { color-scheme: light; --bg: #ffffff; --ink: #111827; --muted: #5b6472; --line: #d8dee8; --panel: #f7f9fc; --card: #ffffff; --accent: #106b62; --link: #075e82; --code: #102033; --soft: #fbfcfe; --reserved: #f3f5f8; --ruler: #f7f9fc; }"
    elif theme == "auto":
        theme_vars = """:root { color-scheme: light dark; --bg: #ffffff; --ink: #111827; --muted: #5b6472; --line: #d8dee8; --panel: #f7f9fc; --card: #ffffff; --accent: #106b62; --link: #075e82; --code: #102033; --soft: #fbfcfe; --reserved: #f3f5f8; --ruler: #f7f9fc; }
@media (prefers-color-scheme: dark) { :root { --bg: #0b0f14; --ink: #e6edf5; --muted: #9aa8b8; --line: #2a3544; --panel: #121923; --card: #101720; --accent: #62d6c7; --link: #8bd3ff; --code: #070a0f; --soft: #111a24; --reserved: #182231; --ruler: #16202d; } }"""
    else:
        theme_vars = ":root { color-scheme: dark; --bg: #0b0f14; --ink: #e6edf5; --muted: #9aa8b8; --line: #2a3544; --panel: #121923; --card: #101720; --accent: #62d6c7; --link: #8bd3ff; --code: #070a0f; --soft: #111a24; --reserved: #182231; --ruler: #16202d; }"
    css = f"""
{theme_vars}
* {{ box-sizing: border-box; }}
body {{ margin: 0; font-family: Inter, system-ui, -apple-system, Segoe UI, sans-serif; color: var(--ink); background: var(--bg); line-height: 1.55; }}
a {{ color: var(--link); text-decoration: none; }}
a:hover {{ text-decoration: underline; }}
header {{ border-bottom: 1px solid var(--line); background: var(--panel); }}
.wrap {{ max-width: 1180px; margin: 0 auto; padding: 24px; }}
.kicker {{ color: var(--accent); font-weight: 700; letter-spacing: .05em; text-transform: uppercase; font-size: 12px; }}
h1 {{ margin: 4px 0 10px; font-size: 34px; line-height: 1.15; }}
h2 {{ margin-top: 34px; padding-bottom: 6px; border-bottom: 1px solid var(--line); }}
h3 {{ margin-top: 24px; }}
.summary {{ color: var(--muted); max-width: 900px; }}
.grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 14px; }}
.card {{ border: 1px solid var(--line); border-radius: 6px; padding: 14px; background: var(--card); }}
.card strong {{ display: block; margin-bottom: 4px; }}
.meta {{ color: var(--muted); font-size: 13px; }}
.datasheet-browser {{ border: 1px solid var(--line); border-radius: 6px; background: var(--card); padding: 14px; }}
.datasheet-search {{ width: 100%; max-width: 460px; border: 1px solid var(--line); border-radius: 6px; background: var(--soft); color: var(--ink); padding: 9px 11px; margin-bottom: 12px; }}
.datasheet-section, .package-group {{ border: 1px solid var(--line); border-radius: 6px; margin: 8px 0; background: var(--soft); }}
.datasheet-section > summary, .package-group > summary {{ cursor: pointer; padding: 8px 10px; font-weight: 700; }}
.package-group {{ margin: 8px 10px; background: var(--card); }}
.datasheet-list {{ max-height: 260px; overflow-y: auto; padding: 4px 10px 10px; }}
.datasheet-link-row {{ display: flex; justify-content: space-between; gap: 12px; padding: 5px 0; border-top: 1px solid var(--line); font-size: 14px; }}
.datasheet-link-row:first-child {{ border-top: 0; }}
.datasheet-link-row .meta {{ white-space: nowrap; }}
.quick-links {{ display: flex; flex-wrap: wrap; gap: 8px; margin-top: 12px; }}
.pill {{ display: inline-flex; align-items: center; gap: 6px; border: 1px solid var(--line); border-radius: 999px; background: var(--soft); color: var(--link); padding: 5px 10px; font-size: 13px; font-weight: 700; }}
.pill:hover {{ text-decoration: none; border-color: var(--accent); }}
.register-index .datasheet-list {{ max-height: 340px; }}
.register-index .datasheet-link-row {{ align-items: baseline; }}
.doc-section {{ border: 1px solid var(--line); border-radius: 6px; background: var(--card); margin: 12px 0; }}
.doc-section > summary {{ cursor: pointer; padding: 10px 12px; font-weight: 700; color: var(--ink); }}
.doc-section-body {{ padding: 0 12px 12px; }}
table {{ width: 100%; border-collapse: collapse; margin: 12px 0 18px; font-size: 14px; }}
th, td {{ border: 1px solid var(--line); padding: 8px 10px; vertical-align: top; text-align: left; }}
th {{ background: var(--panel); font-weight: 700; }}
code, pre {{ font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }}
pre {{ overflow: auto; padding: 14px; border-radius: 6px; background: var(--code); color: #f4f7fb; }}
.diagram {{ overflow-x: auto; padding: 12px 0; }}
.reg-card {{ border: 1px solid var(--line); border-radius: 6px; padding: 12px; margin: 12px 0; background: var(--card); }}
.reg-card h4 {{ margin: 0 0 6px; }}
.reg-meta {{ color: var(--muted); font-size: 13px; margin-bottom: 8px; }}
.reg-slice {{ margin: 10px 0 14px; overflow-x: auto; }}
.reg-slice-title {{ color: var(--muted); font-size: 13px; font-weight: 700; margin: 0 0 4px; text-transform: uppercase; }}
.reg-ruler, .reg-bits {{ display: grid; min-width: 768px; }}
.reg-ruler span {{ font-size: 10px; color: var(--muted); text-align: center; border: 1px solid var(--line); border-bottom: 0; padding: 2px 0; background: var(--ruler); }}
.reg-field {{ min-height: 46px; border: 1px solid var(--line); padding: 5px 6px; font-size: 12px; line-height: 1.15; text-align: center; background: var(--soft); overflow-wrap: anywhere; display: flex; align-items: center; justify-content: center; }}
.reg-field.reserved {{ color: var(--muted); background: var(--reserved); }}
.field-table td:first-child {{ font-weight: 700; white-space: nowrap; }}
.status {{ border-left: 4px solid #d59b35; background: var(--panel); padding: 10px 12px; margin: 10px 0; }}
.testbench-section {{ border: 1px solid var(--line); border-radius: 6px; background: var(--card); margin: 12px 0; }}
.testbench-section > summary {{ cursor: pointer; padding: 10px 12px; font-weight: 700; }}
.testbench-body {{ padding: 0 12px 12px; }}
.wave {{ width: 100%; border: 1px solid var(--line); border-radius: 6px; padding: 10px; background: var(--soft); margin: 12px 0; --wave-zoom: 1; }}
.wave h4 {{ margin: 0 0 8px; }}
.wave-controls {{ display: flex; align-items: center; gap: 8px; margin: 0 0 8px; color: var(--muted); font-size: 13px; }}
.wave-controls input {{ width: 180px; accent-color: var(--accent); }}
.wave-viewport {{ overflow: auto; max-height: 560px; border: 1px solid var(--line); border-radius: 4px; background: var(--card); resize: vertical; }}
.wave svg {{ display: block; width: calc(1120px * var(--wave-zoom)); max-width: none; height: auto; }}
.wave-axis {{ stroke: var(--line); stroke-width: 1; }}
.wave-grid {{ stroke: var(--line); stroke-width: 1; opacity: .65; }}
.wave-grid.clock-grid {{ opacity: .45; }}
.wave-grid.fallback-grid {{ stroke-dasharray: 4 4; }}
.wave-hover-line {{ stroke: #ffd84d; stroke-width: 2; opacity: 0; pointer-events: none; }}
.wave-hover-label {{ fill: #ffd84d; font: 12px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; opacity: 0; pointer-events: none; }}
.wave-label {{ fill: var(--ink); font: 12px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }}
.wave-time {{ fill: var(--muted); font: 11px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }}
.wave-trace {{ fill: none; stroke: var(--accent); stroke-width: 2.2; stroke-linejoin: round; stroke-linecap: round; }}
.wave-bus {{ fill: rgba(98, 214, 199, .12); stroke: var(--accent); stroke-width: 1.2; }}
.wave-bus-text {{ fill: var(--ink); font: 11px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }}
.wave-interface {{ fill: rgba(139, 211, 255, .13); stroke: #8bd3ff; stroke-width: 1.2; }}
.wave-interface-text {{ fill: var(--ink); font: 12px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-weight: 700; }}
.wave-unknown {{ stroke: #d59b35; }}
.wave-group {{ border: 1px solid var(--line); border-radius: 6px; background: var(--card); margin: 10px 0; }}
.wave-group > summary {{ cursor: pointer; padding: 8px 10px; font-weight: 700; }}
.wave-group-body {{ padding: 0 10px 10px; }}
nav.breadcrumb {{ font-size: 13px; color: var(--muted); margin-bottom: 14px; }}
footer {{ margin-top: 42px; border-top: 1px solid var(--line); color: var(--muted); font-size: 13px; }}
""".strip()
    assets = out / "assets"
    assets.mkdir(parents=True, exist_ok=True)
    (assets / "radhdl-docgen.css").write_text(css + "\n", encoding="utf-8")


def page(title: str, body: str, depth: int = 0) -> str:
    prefix = "../" * depth
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
  <link rel="stylesheet" href="{prefix}assets/radhdl-docgen.css">
</head>
<body>
{body}
<script>
document.addEventListener('input', function (event) {{
  if (!event.target.classList || !event.target.classList.contains('wave-zoom')) return;
  var wave = event.target.closest('.wave');
  if (wave) wave.style.setProperty('--wave-zoom', String(Number(event.target.value) / 100));
}});
</script>
</body>
</html>
"""


def paragraph(text: str, fallback: str = "") -> str:
    value = (text or fallback).strip()
    if not value:
        return ""
    return "".join(f"<p>{html.escape(part.strip())}</p>" for part in value.split("\n\n") if part.strip())


def detail_section(title: str, content: str) -> str:
    return f'<details class="doc-section"><summary>{html.escape(title)}</summary><div class="doc-section-body">{content}</div></details>'


def field_table(title: str, fields: list[FieldDoc], include_direction: bool) -> str:
    if not fields:
        return f"<h2>{html.escape(title)}</h2><p class=\"summary\">No {html.escape(title.lower())} declared.</p>"
    heads = ["Name"]
    if include_direction:
        heads.append("Direction")
    heads.extend(["Type", "Default", "Description"] if not include_direction else ["Type", "Description"])
    rows = []
    for field_doc in fields:
        cols = [field_doc.name]
        if include_direction:
            cols.append(field_doc.direction)
            cols.extend([field_doc.data_type, field_doc.description])
        else:
            cols.extend([field_doc.data_type, field_doc.default, field_doc.description])
        rows.append("<tr>" + "".join(f"<td>{html.escape(value)}</td>" for value in cols) + "</tr>")
    return (
        f"<h2>{html.escape(title)}</h2><table><thead><tr>"
        + "".join(f"<th>{html.escape(head)}</th>" for head in heads)
        + "</tr></thead><tbody>"
        + "".join(rows)
        + "</tbody></table>"
    )


def is_register_interface_key(key: str) -> bool:
    upper = key.upper()
    return "AXI_LITE" in upper or upper.startswith("S_AXI") or upper.startswith("M_AXI")


def is_register_port(port: FieldDoc) -> bool:
    lower = port.name.lower()
    if lower.startswith("s_axis") or lower.startswith("m_axis"):
        return False
    return (
        lower.startswith("reg_")
        or lower.startswith("s_axi_")
        or lower.startswith("m_axi_")
        or "axi_lite" in lower
        or re.search(r"(^|_)rd(_|$)|(^|_)wr(_|$)", lower) is not None
    )


def register_interface_groups(module: ModuleDoc) -> dict[str, list[FieldDoc]]:
    groups: dict[str, list[FieldDoc]] = {}
    for port in module.ports:
        key = interface_key(port)
        if key and is_register_interface_key(key):
            groups.setdefault(key, []).append(port)
        elif is_register_port(port):
            groups.setdefault("Register control/status", []).append(port)
    return groups


def render_register_interfaces(module: ModuleDoc) -> str:
    groups = register_interface_groups(module)
    if not groups:
        return ""
    rows = []
    for name in sorted(groups, key=lambda item: (0 if "AXI" in item.upper() else 1, item.upper())):
        ports = groups[name]
        directions = ", ".join(sorted({port.direction for port in ports if port.direction}))
        examples = ", ".join(port.name for port in ports[:8])
        if len(ports) > 8:
            examples += f", +{len(ports) - 8} more"
        rows.append(
            "<tr>"
            f"<td>{html.escape(name)}</td>"
            f"<td>{html.escape(directions)}</td>"
            f"<td>{len(ports)}</td>"
            f"<td>{html.escape(examples)}</td>"
            "</tr>"
        )
    status = (
        "Static register maps are rendered below for this module."
        if module.register_maps
        else "No fixed register map was found; this section documents the exposed register/control interface ports."
    )
    return (
        '<h2 id="register-interfaces">Register Interfaces</h2>'
        f"<p>{html.escape(status)}</p>"
        "<table><thead><tr><th>Interface</th><th>Directions</th><th>Signals</th><th>Representative ports</th></tr></thead><tbody>"
        + "".join(rows)
        + "</tbody></table>"
    )


def interface_key(port: FieldDoc) -> str:
    name = port.name
    upper = name.upper()
    match = re.match(r"^([SM]_AXI(?:S|4|_LITE|_LITE)?)(?:_|$)", upper)
    if match:
        return match.group(1)
    match = re.match(r"^([SM]_AXIS)(?:_|$)", upper)
    if match:
        return match.group(1)
    match = re.match(r"^([SM]_AXI)(?:_|$)", upper)
    if match:
        return match.group(1)
    return ""


def interface_sort_rank(name: str) -> int:
    upper = name.upper()
    if "AXIS" in upper or "_AXIS_" in upper:
        return 0
    if "AXI" in upper or "_AXI_" in upper:
        return 1
    return 2


def interface_side(name: str, members: list[FieldDoc]) -> str:
    upper = name.upper()
    if upper.startswith("M_"):
        return "out"
    if upper.startswith("S_"):
        return "in"
    directions = {member.direction for member in members}
    if directions <= {"out", "buffer"}:
        return "out"
    return "in"


def ordered_ports_for_docs(ports: list[FieldDoc]) -> list[FieldDoc]:
    order = {port.name: index for index, port in enumerate(ports)}
    return sorted(
        ports,
        key=lambda port: (
            interface_sort_rank(interface_key(port) or port.name),
            interface_key(port) or "",
            order.get(port.name, 10**6),
        ),
    )


def diagram_ports(ports: list[FieldDoc]) -> list[DiagramPort]:
    groups: dict[str, list[FieldDoc]] = {}
    passthrough: list[DiagramPort] = []
    for port in ports:
        key = interface_key(port)
        if key:
            groups.setdefault(key, []).append(port)
        else:
            passthrough.append(DiagramPort(name=port.name, direction=port.direction, members=[port]))
    grouped: list[DiagramPort] = []
    for key, members in groups.items():
        if len(members) < 3:
            passthrough.extend(DiagramPort(name=member.name, direction=member.direction, members=[member]) for member in members)
            continue
        grouped.append(DiagramPort(name=key, direction=interface_side(key, members), kind="interface", members=members))
    order = {port.name: index for index, port in enumerate(ports)}
    return sorted(
        grouped + passthrough,
        key=lambda item: (
            interface_sort_rank(item.name),
            item.name.upper() if item.kind == "interface" else "",
            min(order.get(member.name, 10**6) for member in item.members),
        ),
    )


def render_block_svg(module: ModuleDoc) -> str:
    rendered_ports = diagram_ports(module.ports)
    left = [port for port in rendered_ports if port.direction in {"in", "inout"}]
    right = [port for port in rendered_ports if port.direction in {"out", "buffer", "inout"}]
    max_ports = max(len(left), len(right), 1)
    height = max(220, 190 + max_ports * 28)
    left_chars = max([len(port.name) for port in left] + [0])
    right_chars = max([len(port.name) for port in right] + [0])
    title_chars = max(len(module.name), len(module.library) + len(module.kind) + 1)
    text_width = (left_chars + right_chars) * 7 + 120
    title_width = title_chars * 9 + 120
    rect_w = max(420, text_width, title_width)
    rect_x, rect_y, rect_h = 72, 50, height - 90
    width = rect_x + rect_w + 90
    lines = [
        f'<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg" role="img">',
        '<style>text{font-family:Inter,Arial,sans-serif;font-size:13px;fill:#111827}.pin{stroke:#106b62;stroke-width:2;fill:none}.interface-pin{stroke:#7b8794;stroke-width:2;fill:#e5e7eb}.box{fill:#f7f9fc;stroke:#26323f;stroke-width:2}.bubble{fill:#fff;stroke:#106b62;stroke-width:2}.clock{fill:none;stroke:#106b62;stroke-width:2}</style>',
        f'<rect class="box" x="{rect_x}" y="{rect_y}" width="{rect_w}" height="{rect_h}" rx="4"/>',
        f'<text x="{rect_x + rect_w / 2}" y="{rect_y + 34}" text-anchor="middle" font-weight="700">{html.escape(module.name)}</text>',
        f'<text x="{rect_x + rect_w / 2}" y="{rect_y + 56}" text-anchor="middle">{html.escape(module.library)} {html.escape(module.kind)}</text>',
    ]
    def is_clock(port: DiagramPort) -> bool:
        name = port.name.lower()
        return name in {"clk", "clock", "aclk"} or name.endswith("_clk") or name.endswith("clk")

    def is_active_low(port: DiagramPort) -> bool:
        name = port.name.lower()
        return (
            name.endswith("_n")
            or "rstn" in name
            or "resetn" in name
            or "aresetn" in name
            or "enable_n" in name
            or "en_n" in name
        )

    for idx, port in enumerate(left):
        y = rect_y + 80 + idx * 28
        text_x = rect_x + 28
        marker_x = rect_x + 12
        lines.extend(
            [
                f'<line class="pin" x1="{rect_x - 36}" y1="{y}" x2="{rect_x}" y2="{y}"/>',
                f'<text x="{text_x}" y="{y + 4}">{html.escape(port.name)}</text>',
            ]
        )
        if port.kind == "interface":
            lines.append(f'<rect class="interface-pin" x="{rect_x - 44}" y="{y - 9}" width="18" height="18" rx="2"/>')
        elif is_clock(port):
            lines.append(f'<path class="clock" d="M {rect_x + 2} {y - 7} L {rect_x + 15} {y} L {rect_x + 2} {y + 7}"/>')
        elif is_active_low(port):
            lines.append(f'<circle class="bubble" cx="{marker_x}" cy="{y}" r="5"/>')
    for idx, port in enumerate(right):
        y = rect_y + 80 + idx * 28
        text_x = rect_x + rect_w - 28
        marker_x = rect_x + rect_w - 12
        lines.extend(
            [
                f'<line class="pin" x1="{rect_x + rect_w}" y1="{y}" x2="{rect_x + rect_w + 36}" y2="{y}"/>',
                f'<text x="{text_x}" y="{y + 4}" text-anchor="end">{html.escape(port.name)}</text>',
            ]
        )
        if port.kind == "interface":
            lines.append(f'<rect class="interface-pin" x="{rect_x + rect_w + 26}" y="{y - 9}" width="18" height="18" rx="2"/>')
        elif is_clock(port):
            lines.append(f'<path class="clock" d="M {rect_x + rect_w - 2} {y - 7} L {rect_x + rect_w - 15} {y} L {rect_x + rect_w - 2} {y + 7}"/>')
        elif is_active_low(port):
            lines.append(f'<circle class="bubble" cx="{marker_x}" cy="{y}" r="5"/>')
    lines.append("</svg>")
    return "\n".join(lines)


def register_segments(register: RegisterDoc) -> list[dict[str, Any]]:
    width = max(1, min(register.width or 32, 64))
    fields = []
    for field_doc in register.fields:
        msb = min(width - 1, int(field_doc["msb"]))
        lsb = max(0, int(field_doc["lsb"]))
        if msb >= lsb:
            fields.append(
                {
                    "name": str(field_doc.get("display_name") or field_doc["name"]),
                    "full_name": str(field_doc["name"]),
                    "description": str(field_doc.get("description") or field_description(str(field_doc["name"]))),
                    "msb": msb,
                    "lsb": lsb,
                    "reserved": False,
                }
            )
    if not fields:
        return [{"name": "VALUE", "full_name": "value", "description": "Full register value.", "msb": width - 1, "lsb": 0, "reserved": False}]
    fields.sort(key=lambda item: item["msb"], reverse=True)
    segments: list[dict[str, Any]] = []
    cursor = width - 1
    for field_doc in fields:
        if field_doc["msb"] < cursor:
            segments.append({"name": "RSVD", "msb": cursor, "lsb": field_doc["msb"] + 1, "reserved": True})
        segments.append(field_doc)
        cursor = field_doc["lsb"] - 1
    if cursor >= 0:
        segments.append({"name": "RSVD", "msb": cursor, "lsb": 0, "reserved": True})
    return segments


def display_register_name(name: str) -> str:
    return "".join(part[:1].upper() + part[1:] for part in re.split(r"[_\s-]+", name) if part)


def compact_hex(value: str) -> str:
    parsed = int_value(value)
    if parsed is None:
        return value
    width = 4 if parsed >= 0x1000 else 2
    return f"0x{parsed:0{width}X}"


def bit_ref(register: RegisterDoc, segment: dict[str, Any]) -> str:
    name = display_register_name(register.name)
    msb = int(segment["msb"])
    lsb = int(segment["lsb"])
    return f"{name}[{msb}]" if msb == lsb else f"{name}[{msb}:{lsb}]"


def render_register_slice(register: RegisterDoc, high: int, low: int) -> str:
    slice_width = high - low + 1
    ruler = "".join(f"<span>{bit}</span>" for bit in range(high, low - 1, -1))
    fields = []
    for segment in register_segments(register):
        msb = min(high, int(segment["msb"]))
        lsb = max(low, int(segment["lsb"]))
        if msb < lsb:
            continue
        span = msb - lsb + 1
        start = high - msb + 1
        label = segment["name"] if msb == lsb else f"{segment['name']} [{msb}:{lsb}]"
        css = "reg-field reserved" if segment.get("reserved") else "reg-field"
        fields.append(f'<div class="{css}" style="grid-column: {start} / span {span};">{html.escape(label)}</div>')
    return (
        '<div class="reg-slice">'
        f'<div class="reg-slice-title">{html.escape(display_register_name(register.name))}[{high}:{low}]</div>'
        f'<div class="reg-ruler" style="grid-template-columns: repeat({slice_width}, minmax(48px, 1fr));">{ruler}</div>'
        f'<div class="reg-bits" style="grid-template-columns: repeat({slice_width}, minmax(48px, 1fr));">{"".join(fields)}</div>'
        "</div>"
    )


def render_register_block(register: RegisterDoc) -> str:
    width = max(1, min(register.width or 32, 64))
    chunks = []
    for low in range(0, width, 16):
        high = min(width - 1, low + 15)
        chunks.append(render_register_slice(register, high, low))
    return "".join(chunks)


def render_register_field_table(register: RegisterDoc) -> str:
    rows = []
    for segment in register_segments(register):
        if segment.get("reserved"):
            continue
        rows.append(
            "<tr>"
            f"<td>{html.escape(str(segment['name']))}</td>"
            f"<td>{html.escape(bit_ref(register, segment))}</td>"
            f"<td>{html.escape(str(segment.get('description', '')))}</td>"
            "</tr>"
        )
    if not rows:
        return ""
    return (
        '<table class="field-table"><thead><tr><th>Name</th><th>Register bit(s)</th><th>Description</th></tr></thead><tbody>'
        + "".join(rows)
        + "</tbody></table>"
    )


def render_register_maps(module: ModuleDoc) -> str:
    if not module.register_maps:
        return ""
    parts = ['<h2 id="register-maps">Register Maps</h2>']
    for regmap in module.register_maps:
        parts.append(f"<h3>{html.escape(regmap.name)}</h3>")
        parts.append(f'<p class="meta">Source: {html.escape(regmap.path)}</p>')
        parts.append(paragraph(regmap.description))
        if not regmap.registers:
            parts.append('<p class="summary">No registers declared in this map.</p>')
            continue
        rows = []
        for register in regmap.registers:
            rows.append(
                "<tr>"
                f"<td>{html.escape(register.name)}</td>"
                f"<td>{html.escape(compact_hex(register.offset))}</td>"
                f"<td>{html.escape(register.access)}</td>"
                f"<td>{html.escape(register.reset)}</td>"
                f"<td>{html.escape(register.description)}</td>"
                "</tr>"
            )
        parts.append(
            "<table><thead><tr><th>Register</th><th>Offset</th><th>Access</th><th>Reset</th><th>Description</th></tr></thead><tbody>"
            + "".join(rows)
            + "</tbody></table>"
        )
        for register in regmap.registers:
            meta_items = [
                item
                for item in [
                    f"Offset {compact_hex(register.offset)}" if register.offset else "",
                    f"Access {register.access}" if register.access else "",
                    f"Reset {register.reset}" if register.reset else "",
                ]
                if item
            ]
            parts.append(
                '<div class="reg-card">'
                f"<h4>{html.escape(register.name)}</h4>"
                f'<div class="reg-meta">{html.escape(" / ".join(meta_items))}</div>'
                + paragraph(register.description)
                + render_register_block(register)
                + render_register_field_table(register)
                + "</div>"
            )
    return "".join(parts)


def use_cases(module: ModuleDoc) -> list[str]:
    name = module.name.lower()
    cases: list[str] = []
    if "axis" in name or "stream" in name:
        cases.append("AXI-Stream datapath integration where module boundaries need explicit ready/valid behavior.")
    if "fir" in name or "biquad" in name or "dds" in name or "fft" in name or "cordic" in name:
        cases.append("Reusable FPGA DSP pipelines that need fixed-point, timing-aware implementation.")
    if "axi" in name or "reg" in name:
        cases.append("Memory-mapped control/status integration with software-visible register maps.")
    if "ila" in name or module.category == "Debug":
        cases.append("Debug and observability hooks for generated FPGA systems.")
    if not cases:
        cases.append("Reusable RadHDL building block for graph-generated FPGA systems.")
    return cases


def vhdl_include_template(module: ModuleDoc) -> str:
    library = module.library if module.library else "radhdl"
    if module.category == "DSP":
        subgroup = f"dsp_{dsp_package_group(module).lower()}"
        umbrella = "dsp"
    elif module.category == "Interfaces":
        subgroup = interface_include_package(module)
        umbrella = "interfaces"
    elif module.category == "Debug":
        subgroup = "debug"
        umbrella = "debug"
    else:
        subgroup = ""
        umbrella = ""
    lines = [
        "library ieee;",
        "use ieee.std_logic_1164.all;",
        "use ieee.numeric_std.all;",
        "",
        f"library {library};",
        "-- Direct entity instantiation below does not require importing the entity name.",
    ]
    if umbrella:
        lines.append(f"use {library}.{umbrella}.all;")
    if subgroup and subgroup != umbrella:
        lines.append(f"-- Narrower alternative: use {library}.{subgroup}.all;")
    return "\n".join(lines)


def association_template(fields: list[FieldDoc], value_fn) -> str:
    if not fields:
        return ""
    width = max(len(field.name) for field in fields)
    return ",\n".join(f"    {field.name.ljust(width)} => {value_fn(field)}" for field in fields)


def declaration_list(fields: list[FieldDoc], line_fn) -> list[str]:
    lines: list[str] = []
    for index, field in enumerate(fields):
        suffix = ";" if index < len(fields) - 1 else ""
        lines.append(f"    {line_fn(field)}{suffix}")
    return lines


def vhdl_component_template(module: ModuleDoc) -> str:
    lines = [f"component {module.name} is"]
    if module.generics:
        lines.append("  generic (")
        lines.extend(
            declaration_list(
                module.generics,
                lambda field: f"{field.name} : {field.data_type}{f' := {field.default}' if field.default else ''}",
            )
        )
        lines.append("  );")
    ports = ordered_ports_for_docs(module.ports)
    if ports:
        lines.append("  port (")
        lines.extend(declaration_list(ports, lambda field: f"{field.name} : {field.direction} {field.data_type}"))
        lines.append("  );")
    else:
        lines.append("  -- No ports declared.")
    lines.append("end component;")
    return "\n".join(lines)


def vhdl_instantiation_template(module: ModuleDoc) -> str:
    generic_map = association_template(module.generics, lambda field: field.default or f"<{field.name.lower()}_value>")
    port_map = association_template(ordered_ports_for_docs(module.ports), lambda field: f"<{field.name.lower()}_signal>")
    lines = [f"u_{module.name.lower()} : entity {module.library}.{module.name}"]
    if generic_map:
        lines.append("  generic map (")
        lines.append(generic_map)
        lines.append("  )")
    lines.append("  port map (")
    lines.append(port_map or "    -- No ports declared.")
    lines.append("  );")
    return "\n".join(lines)


def render_integration_template(module: ModuleDoc) -> str:
    content = (
        "<h3>File Header</h3>"
        f"<pre><code>{html.escape(vhdl_include_template(module))}</code></pre>"
        "<h3>Component Declaration</h3>"
        f"<pre><code>{html.escape(vhdl_component_template(module))}</code></pre>"
        "<h3>Direct Entity Instantiation</h3>"
        f"<pre><code>{html.escape(vhdl_instantiation_template(module))}</code></pre>"
    )
    return detail_section("VHDL Include And Instantiation Template", content)


def normalize_wave_value(value: str) -> str:
    return value.strip().replace("_", "")


def is_scalar_wave(samples: list[tuple[int, str]]) -> bool:
    return all(len(normalize_wave_value(value)) == 1 for _, value in samples)


def wave_y(value: str, high_y: float, low_y: float) -> float:
    normalized = normalize_wave_value(value).lower()
    if normalized == "1":
        return high_y
    if normalized == "0":
        return low_y
    return (high_y + low_y) / 2


def wave_x(time_value: int, end_time: int, x0: int, width: int) -> float:
    if end_time <= 0:
        return float(x0)
    return x0 + (max(0, min(time_value, end_time)) / end_time) * width


def format_wave_value(value: str) -> str:
    normalized = normalize_wave_value(value)
    if not normalized:
        return ""
    if len(normalized) > 8 and set(normalized.lower()) <= {"0", "1"}:
        return f"0x{int(normalized, 2):X}"
    if len(normalized) > 18:
        return normalized[:15] + "..."
    return normalized.upper()


def compact_wave_samples(samples: list[tuple[int, str]], limit: int = 72) -> list[tuple[int, str]]:
    compacted: list[tuple[int, str]] = []
    previous: tuple[int, str] | None = None
    for time_value, value in sorted(samples, key=lambda item: item[0]):
        value = normalize_wave_value(value)
        if previous and previous[0] == time_value:
            compacted[-1] = (time_value, value)
        elif not previous or previous[1] != value:
            compacted.append((time_value, value))
        previous = (time_value, value)
        if len(compacted) >= limit:
            break
    return compacted


def scalar_wave_path(samples: list[tuple[int, str]], end_time: int, x0: int, width: int, y0: int, height: int) -> tuple[str, bool]:
    samples = compact_wave_samples(samples)
    if not samples:
        return "", False
    high_y = y0
    low_y = y0 + height
    path: list[str] = []
    unknown = False
    first_time, first_value = samples[0]
    current_x = wave_x(first_time, end_time, x0, width)
    current_y = wave_y(first_value, high_y, low_y)
    unknown = unknown or normalize_wave_value(first_value).lower() not in {"0", "1"}
    path.append(f"M {current_x:.1f} {current_y:.1f}")
    for time_value, value in samples[1:]:
        next_x = wave_x(time_value, end_time, x0, width)
        next_y = wave_y(value, high_y, low_y)
        path.append(f"L {next_x:.1f} {current_y:.1f}")
        path.append(f"L {next_x:.1f} {next_y:.1f}")
        current_x = next_x
        current_y = next_y
        unknown = unknown or normalize_wave_value(value).lower() not in {"0", "1"}
    path.append(f"L {wave_x(end_time, end_time, x0, width):.1f} {current_y:.1f}")
    return " ".join(path), unknown


def render_bus_wave(samples: list[tuple[int, str]], end_time: int, x0: int, width: int, y0: int, height: int) -> str:
    samples = compact_wave_samples(samples)
    if not samples:
        return ""
    elements = []
    mid_y = y0 + height / 2
    for index, (time_value, value) in enumerate(samples):
        next_time = samples[index + 1][0] if index + 1 < len(samples) else end_time
        x1 = wave_x(time_value, end_time, x0, width)
        x2 = max(x1 + 4, wave_x(next_time, end_time, x0, width))
        label = format_wave_value(value)
        elements.append(f'<rect class="wave-bus" x="{x1:.1f}" y="{y0}" width="{max(4, x2 - x1):.1f}" height="{height}" rx="3" />')
        if x2 - x1 >= 34 and label:
            elements.append(f'<text class="wave-bus-text" x="{x1 + 5:.1f}" y="{mid_y + 4:.1f}">{html.escape(label)}</text>')
    return "".join(elements)


def is_clock_wave_signal(signal: dict[str, Any]) -> bool:
    name = str(signal.get("name", "")).lower()
    return name in {"clk", "clock", "aclk"} or name.endswith("_clk") or name.endswith("clk")


def clock_grid_times(signals: list[dict[str, Any]], end_time: int) -> list[int]:
    clocks = [signal for signal in signals if is_clock_wave_signal(signal) and is_scalar_wave(signal.get("samples", []))]
    if not clocks:
        return []
    samples = [(int(time), str(value).lower()) for time, value in clocks[0].get("samples", [])]
    rising: list[int] = []
    previous = ""
    for time_value, value in samples:
        if previous == "0" and value == "1":
            rising.append(time_value)
        previous = value
    if len(rising) < 2:
        return []
    period = max(1, rising[1] - rising[0])
    ticks = list(range(rising[0], end_time + period, period))
    if len(ticks) > 240:
        stride = max(1, len(ticks) // 240)
        ticks = ticks[::stride]
    return ticks


def waveform_grid_times(signals: list[dict[str, Any]], end_time: int) -> tuple[list[int], bool]:
    ticks = clock_grid_times(signals, end_time)
    if ticks:
        return ticks, True
    fallback = sorted({int(end_time * fraction) for fraction in (0, 0.25, 0.5, 0.75, 1)})
    return fallback or [0], False


def waveform_script() -> str:
    return """
<script>
(() => {
  document.querySelectorAll(".wave").forEach((wave) => {
    if (wave.dataset.ready === "1") return;
    wave.dataset.ready = "1";
    const zoom = wave.querySelector(".wave-zoom");
    const svg = wave.querySelector("svg.waveform");
    const hover = wave.querySelector(".wave-hover-line");
    const hoverLabel = wave.querySelector(".wave-hover-label");
    const labels = Array.from(wave.querySelectorAll(".wave-time"));
    const grids = Array.from(wave.querySelectorAll(".wave-grid"));
    const clockGrids = grids.filter((grid) => grid.dataset.clock === "1");
    const snapGrids = clockGrids.length ? clockGrids : grids;
    const setZoom = () => {
      const value = zoom ? Number(zoom.value) / 100 : 1;
      wave.style.setProperty("--wave-zoom", String(value));
      const every = value >= 2.4 ? 1 : value >= 1.5 ? 2 : 4;
      labels.forEach((label, index) => {
        label.style.display = index % every === 0 ? "" : "none";
      });
    };
    setZoom();
    if (zoom) zoom.addEventListener("input", setZoom);
    if (!svg || !hover || !hoverLabel || !snapGrids.length) return;
    const nearest = (x) => {
      let best = snapGrids[0];
      let bestDistance = Math.abs(Number(best.dataset.x) - x);
      snapGrids.forEach((line) => {
        const distance = Math.abs(Number(line.dataset.x) - x);
        if (distance < bestDistance) {
          best = line;
          bestDistance = distance;
        }
      });
      return best;
    };
    svg.addEventListener("mousemove", (event) => {
      const point = svg.createSVGPoint();
      point.x = event.clientX;
      point.y = event.clientY;
      const matrix = svg.getScreenCTM();
      if (!matrix) return;
      const local = point.matrixTransform(matrix.inverse());
      const line = nearest(local.x);
      const x = Number(line.dataset.x);
      hover.setAttribute("x1", x);
      hover.setAttribute("x2", x);
      hover.style.opacity = "1";
      hoverLabel.setAttribute("x", x + 4);
      hoverLabel.textContent = `t=${line.dataset.time}`;
      hoverLabel.style.opacity = "1";
    });
    svg.addEventListener("mouseleave", () => {
      hover.style.opacity = "0";
      hoverLabel.style.opacity = "0";
    });
  });
})();
</script>
""".strip()


def wave_interface_key(name: str) -> str:
    upper = re.sub(r"\[[^\]]+\]$", "", name.upper())
    patterns = [
        r"^([SM]_AXIS)(?:_|$)",
        r"^([SM]_AXI(?:4|_LITE|LITE)?)(?:_|$)",
        r"^(M_AXI|S_AXI)(?:_|$)",
        r"^(QSPI|I2C|SPI|SMI)(?:_|$)",
    ]
    for pattern in patterns:
        match = re.match(pattern, upper)
        if match:
            return match.group(1).replace("AXILITE", "AXI_LITE")
    return ""


def group_wave_signals(signals: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], dict[str, list[dict[str, Any]]]]:
    groups: dict[str, list[dict[str, Any]]] = {}
    overview: list[dict[str, Any]] = []
    for signal in signals:
        key = wave_interface_key(str(signal.get("name", "")))
        if key:
            groups.setdefault(key, []).append(signal)
        else:
            overview.append(signal)
    for key, members in groups.items():
        summary_samples = []
        for member in members:
            summary_samples.extend(member.get("samples", []))
        overview.append({"name": key, "kind": "interface", "count": len(members), "samples": compact_wave_samples(summary_samples, 96)})
    return overview, groups


def render_waveform_svg(
    signals: list[dict[str, Any]],
    title: str,
    source: str = "",
    max_signals: int = 96,
    grid_signals: list[dict[str, Any]] | None = None,
) -> str:
    selected = [signal for signal in signals if signal.get("samples")][:max_signals]
    if not selected:
        return ""
    end_time = max((time for signal in selected for time, _ in signal["samples"]), default=1)
    end_time = max(1, end_time)
    width = 1120
    label_width = 190
    plot_width = width - label_width - 36
    top = 34
    row_height = 34
    trace_height = 16
    height = top + len(selected) * row_height + 28
    grid = []
    ticks, clock_based = waveform_grid_times(grid_signals or selected, end_time)
    grid_class = "wave-grid clock-grid" if clock_based else "wave-grid fallback-grid"
    for tick_index, time_value in enumerate(ticks):
        x = label_width + (time_value / end_time) * plot_width
        grid.append(
            f'<line class="{grid_class}" data-clock="{1 if clock_based else 0}" data-x="{x:.1f}" data-time="{time_value}" '
            f'x1="{x:.1f}" y1="20" x2="{x:.1f}" y2="{height - 18}" />'
        )
        grid.append(f'<text class="wave-time" data-tick="{tick_index}" x="{x + 3:.1f}" y="15">{time_value}</text>')
    rows = []
    for index, signal in enumerate(selected):
        row_y = top + index * row_height
        trace_y = row_y + 4
        label = str(signal["name"])
        rows.append(f'<text class="wave-label" x="8" y="{row_y + 18}">{html.escape(label)}</text>')
        rows.append(f'<line class="wave-axis" x1="{label_width}" y1="{trace_y + trace_height}" x2="{label_width + plot_width}" y2="{trace_y + trace_height}" />')
        samples = signal["samples"]
        if signal.get("kind") == "interface":
            rows.append(f'<rect class="wave-interface" x="{label_width}" y="{trace_y - 1}" width="{plot_width}" height="{trace_height + 2}" rx="4" />')
            rows.append(
                f'<text class="wave-interface-text" x="{label_width + 8}" y="{trace_y + 12}">'
                f'{html.escape(label)} interface ({int(signal.get("count", 0))} signals)</text>'
            )
        elif is_scalar_wave(samples):
            path, unknown = scalar_wave_path(samples, end_time, label_width, plot_width, trace_y, trace_height)
            if path:
                css = "wave-trace wave-unknown" if unknown else "wave-trace"
                rows.append(f'<path class="{css}" d="{path}" />')
        else:
            rows.append(render_bus_wave(samples, end_time, label_width, plot_width, trace_y, trace_height))
    source_html = f'<p class="meta">Source: {html.escape(source)}</p>' if source else ""
    return (
        '<div class="wave">'
        f"<h4>{html.escape(title)}</h4>"
        f"{source_html}"
        '<div class="wave-controls"><label>Zoom <input class="wave-zoom" type="range" min="80" max="320" value="100"></label></div>'
        '<div class="wave-viewport">'
        f'<svg class="waveform" viewBox="0 0 {width} {height}" role="img" aria-label="{html.escape(title)}">'
        + "".join(grid)
        + "".join(rows)
        + f'<line class="wave-hover-line" x1="{label_width}" y1="20" x2="{label_width}" y2="{height - 18}" />'
        + f'<text class="wave-hover-label" x="{label_width + 4}" y="{height - 6}"></text>'
        + "</svg></div>"
        + waveform_script()
        + "</div>"
    )


def render_waveform_viewer(signals: list[dict[str, Any]], title: str, source: str) -> str:
    overview, groups = group_wave_signals(signals)
    parts = [render_waveform_svg(overview, title, source, grid_signals=signals)]
    for key in sorted(groups):
        parts.append(
            '<details class="wave-group">'
            f"<summary>{html.escape(key)} interface signals</summary>"
            '<div class="wave-group-body">'
            + render_waveform_svg(groups[key], f"{key} Interface Waveform", source, grid_signals=signals)
            + "</div></details>"
        )
    return "".join(parts)


def vcd_wave_signals(vcd_path: Path) -> list[dict[str, Any]]:
    if not vcd_path.exists():
        return []
    signals: dict[str, str] = {}
    samples: dict[str, list[tuple[int, str]]] = {}
    current_time = 0
    for raw in vcd_path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if line.startswith("$var"):
            parts = line.split()
            if len(parts) >= 5:
                code = parts[3]
                name = parts[4]
                signals[code] = name
                samples.setdefault(code, [])
        elif line.startswith("#"):
            try:
                current_time = int(line[1:])
            except ValueError:
                pass
        elif line and (line[0] in "01xXzZ" or line[0] == "b"):
            if line[0] == "b":
                value, code = line.split(maxsplit=1)
                value = value[1:]
            else:
                value, code = line[0], line[1:]
            if code in samples and len(samples[code]) < 768:
                samples[code].append((current_time, value))
    wave_signals = []
    seen_names: set[str] = set()
    for code, name in signals.items():
        if name in seen_names:
            continue
        seen_names.add(name)
        signal_samples = compact_wave_samples(samples.get(code, []))
        if signal_samples:
            wave_signals.append({"name": name, "samples": signal_samples})
    return wave_signals


def render_vcd_preview(vcd_path: Path, source: str) -> str:
    return render_waveform_viewer(vcd_wave_signals(vcd_path), "Captured GHDL Waveform", source)


def portable_timing_samples(name: str, data_type: str, index: int) -> list[tuple[int, str]]:
    lowered = name.lower()
    active_low = lowered.endswith("_n") or lowered.endswith("n") or "aresetn" in lowered
    if "clk" in lowered or "clock" in lowered:
        samples = []
        value = "0"
        for time_value in range(0, 121, 5):
            samples.append((time_value, value))
            value = "1" if value == "0" else "0"
        return samples
    if "rst" in lowered or "reset" in lowered:
        return [(0, "0" if active_low else "1"), (18, "1" if active_low else "0")]
    if any(token in lowered for token in ("valid", "ready", "enable", "start")):
        base = 22 + index * 3
        return [(0, "0"), (base, "1"), (base + 48, "0"), (base + 74, "1")]
    if any(token in lowered for token in ("done", "last", "irq")):
        base = 76 + index * 2
        return [(0, "0"), (base, "1"), (base + 12, "0")]
    if any(token in lowered for token in ("data", "addr", "count", "len", "tdata")) or "vector" in data_type.lower():
        return [(0, "0" * 8), (24, "00010010"), (54, "10100101"), (92, "00111100")]
    return [(0, "0"), (36 + index * 2, "1"), (88 + index * 2, "0")]


def render_port_waveform_sketch(module: ModuleDoc, source: str) -> str:
    ports = ordered_ports_for_docs(module.ports)
    prioritized = sorted(
        ports,
        key=lambda port: (
            0 if re.search(r"clk|clock", port.name, re.IGNORECASE) else
            1 if re.search(r"rst|reset", port.name, re.IGNORECASE) else
            2 if re.search(r"valid|ready|enable|start|done|last|irq", port.name, re.IGNORECASE) else
            3 if re.search(r"data|addr|count|len|tdata", port.name, re.IGNORECASE) else
            4,
            port.name,
        ),
    )
    signals = [
        {"name": port.name, "samples": portable_timing_samples(port.name, port.data_type, index)}
        for index, port in enumerate(prioritized)
    ]
    return render_waveform_viewer(signals, "Interface Timing Diagram", source)


def imported_libraries(text: str) -> set[str]:
    libraries = set()
    for match in re.finditer(r"^\s*library\s+([^;]+);", text, re.IGNORECASE | re.MULTILINE):
        for name in match.group(1).split(","):
            lib = name.strip().lower()
            if lib and lib not in {"ieee", "std", "work"}:
                libraries.add(lib)
    return libraries


def is_vendor_bound_source(path: Path) -> bool:
    text = read_text(path).lower()
    libraries = imported_libraries(text)
    if libraries & VENDOR_SIM_LIBRARIES:
        return True
    return False


def source_priority(path: Path) -> tuple[int, str]:
    text = read_text(path)
    if PACKAGE_RE.search(text):
        return (0, str(path))
    return (1, str(path))


def library_sources(root: Path, library: str) -> list[Path]:
    sources: list[Path] = []
    for rel in HDL_LIBRARY_DIRS.get(library, ()):
        base = root / rel
        if not base.exists():
            continue
        for path in sorted(base.rglob("*")):
            if path.is_file() and path.suffix.lower() in HDL_SUFFIXES and not should_skip(path, root):
                if "testbench" not in rel_path(path, root).lower() and not is_vendor_bound_source(path):
                    sources.append(path)
    for rel in HDL_SIM_MODEL_DIRS.get(library, ()):
        base = root / rel
        if not base.exists():
            continue
        for path in sorted(base.rglob("*")):
            if path.is_file() and path.suffix.lower() in HDL_SUFFIXES:
                sources.append(path)
    return sorted(sources, key=source_priority)


def testbench_work_sources(testbench: Path, root: Path, libraries: list[str]) -> list[Path]:
    sources: list[Path] = []
    for path in sorted(testbench.parent.glob("*.vhd")):
        if path == testbench or should_skip(path, root):
            continue
        text = read_text(path)
        if PACKAGE_RE.search(text):
            sources.append(path)
    for library in libraries:
        for rel in HDL_SIM_MODEL_DIRS.get(library, ()):
            base = root / rel
            if not base.exists():
                continue
            for path in sorted(base.rglob("*")):
                if path.is_file() and path.suffix.lower() in HDL_SUFFIXES:
                    sources.append(path)
    if "debug/radila" in rel_path(testbench, root):
        sources.extend(library_sources(root, "radila"))
    sources.append(testbench)
    return list(dict.fromkeys(sources))


def run_ghdl_command(command: list[str], work: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=work, check=True, capture_output=True, text=True)


def sanitize_public_paths(value: Any, root: Path, out: Path) -> Any:
    if isinstance(value, dict):
        return {key: sanitize_public_paths(item, root, out) for key, item in value.items()}
    if isinstance(value, list):
        return [sanitize_public_paths(item, root, out) for item in value]
    if isinstance(value, str):
        replacements = {
            str(root.resolve()) + os.sep: "",
            str(out.resolve()) + os.sep: "",
            str(root.resolve()): root.name,
            str(out.resolve()): "",
        }
        sanitized = value
        for needle, replacement in replacements.items():
            sanitized = sanitized.replace(needle, replacement)
        return sanitized
    return value


def analyze_sources(
    ghdl: str,
    root: Path,
    work: Path,
    library: str,
    sources: list[Path],
    status: dict[str, Any],
) -> None:
    pending = list(dict.fromkeys(sources))
    failed: dict[str, str] = {}
    analyzed: list[str] = []
    progress = True
    while pending and progress:
        progress = False
        remaining: list[Path] = []
        for source in pending:
            command = [ghdl, "-a", *GHDL_BASE_ARGS, f"-P{work}", f"--work={library}", f"--workdir={work}", str(source)]
            try:
                run_ghdl_command(command, work)
                analyzed.append(rel_path(source, root))
                failed.pop(str(source), None)
                progress = True
            except subprocess.CalledProcessError as exc:
                failed[str(source)] = (exc.stderr or exc.stdout or "").strip()[-1200:]
                remaining.append(source)
        pending = remaining
    status.setdefault("analyzed", {}).setdefault(library, []).extend(analyzed)
    if pending:
        status.setdefault("analysis_skipped", {}).setdefault(library, [])
        for source in pending:
            status["analysis_skipped"][library].append({"path": rel_path(source, root), "reason": failed.get(str(source), "analysis failed")})


def run_ghdl(testbench: TestbenchDoc, root: Path, out: Path, strict: bool = False, stop_time: str = "100us") -> dict[str, Any]:
    ghdl = shutil.which("ghdl")
    sim_dir = out / "simulations" / module_slug(testbench.name)
    sim_dir.mkdir(parents=True, exist_ok=True)
    status = {"backend": "ghdl", "testbench": testbench.name, "status": "skipped", "reason": "ghdl not found"}
    if not ghdl:
        if strict:
            raise RuntimeError("ghdl not found")
        (sim_dir / "simulation_status.json").write_text(json.dumps(status, indent=2) + "\n", encoding="utf-8")
        return status
    tb_path = root / testbench.path
    tb_text = read_text(tb_path)
    libraries = sorted(imported_libraries(tb_text) & set(HDL_LIBRARY_DIRS))
    if not libraries:
        if "dsp/hdl/testbenches" in testbench.path:
            libraries.append("raddsp")
        elif "interfaces/hdl/radif/testbenches" in testbench.path:
            libraries.append("radif")
        elif "debug/radila" in testbench.path:
            libraries.append("radila")
    with tempfile.TemporaryDirectory(prefix="radhdl-ghdl-") as td:
        work = Path(td)
        status = {"backend": "ghdl", "testbench": testbench.name, "status": "running", "libraries": libraries}
        try:
            if (root / "sim/xpm").exists():
                analyze_sources(ghdl, root, work, "xpm", library_sources(root, "xpm"), status)
            for library in libraries:
                analyze_sources(ghdl, root, work, library, library_sources(root, library), status)
            analyze_sources(ghdl, root, work, "work", testbench_work_sources(tb_path, root, libraries), status)
            run_ghdl_command([ghdl, "-e", *GHDL_BASE_ARGS, f"-P{work}", f"--workdir={work}", testbench.name], work)
            vcd = sim_dir / f"{testbench.name}.vcd"
            completed = run_ghdl_command(
                [ghdl, "-r", *GHDL_BASE_ARGS, f"-P{work}", f"--workdir={work}", testbench.name, f"--vcd={vcd}", f"--stop-time={stop_time}"],
                work,
            )
            status.update(
                {
                    "status": "passed",
                    "vcd": str(vcd.relative_to(out)),
                    "stdout": completed.stdout[-4000:] if completed.stdout else "",
                    "stderr": completed.stderr[-4000:] if completed.stderr else "",
                }
            )
        except subprocess.CalledProcessError as exc:
            failed_vcd = sim_dir / f"{testbench.name}.vcd"
            if failed_vcd.exists():
                failed_vcd.unlink()
            status.update(
                {
                    "status": "failed",
                    "returncode": exc.returncode,
                    "stdout": exc.stdout[-4000:] if exc.stdout else "",
                    "stderr": exc.stderr[-4000:] if exc.stderr else "",
                }
            )
            if strict:
                raise RuntimeError(f"GHDL simulation failed for {testbench.name}: {exc.stderr}") from exc
    status = sanitize_public_paths(status, root, out)
    (sim_dir / "simulation_status.json").write_text(json.dumps(status, indent=2) + "\n", encoding="utf-8")
    return status


def render_testbenches(
    module: ModuleDoc,
    root: Path,
    out: Path,
    run_sims: bool,
    strict: bool,
    stop_time: str,
    sim_cache: dict[str, dict[str, Any]],
) -> str:
    parts = ['<h2 id="testbenches">Testbenches</h2>']
    if not module.testbenches:
        parts.append('<p class="summary">No directly associated testbench was found.</p>')
        return "".join(parts)
    rendered = 0
    for bench in module.testbenches:
        status = bench.simulation
        if run_sims:
            status = sim_cache.get(bench.name)
            if status is None:
                status = run_ghdl(bench, root, out, strict, stop_time)
                sim_cache[bench.name] = status
            bench.simulation = status
        state = status.get("status", "not-run") if status else "not-run"
        if run_sims and state != "passed":
            continue
        artifact_links = []
        status_path = Path("..") / ".." / "simulations" / module_slug(bench.name) / "simulation_status.json"
        if status:
            artifact_links.append(f'<a href="{html.escape(str(status_path))}">status</a>')
        if status.get("vcd") and state == "passed":
            vcd_path = Path("..") / ".." / "simulations" / module_slug(bench.name) / f"{module_slug(bench.name)}.vcd"
            artifact_links.append(f'<a href="{html.escape(str(vcd_path))}">vcd</a>')
        if status.get("vcd") and state == "passed":
            waveform = render_vcd_preview(out / status["vcd"], bench.path)
        elif not run_sims:
            waveform = render_port_waveform_sketch(module, bench.path)
        else:
            waveform = ""
        artifact_html = f'<p class="meta">Artifacts: {", ".join(artifact_links)}</p>' if artifact_links else ""
        status_label = "captured waveform" if status.get("vcd") and state == "passed" else "interface timing diagram" if waveform else "waveform unavailable"
        parts.append(
            '<details class="testbench-section">'
            f'<summary>{html.escape(bench.name)} <span class="meta">{html.escape(status_label)}</span></summary>'
            '<div class="testbench-body">'
            f'<p class="meta">Source: {html.escape(bench.path)}</p>'
            f'{paragraph(bench.description, "No testbench description has been written yet.")}'
            f"{artifact_html}"
            f"{waveform}"
            "</div></details>"
        )
        rendered += 1
    if rendered == 0:
        parts.append('<p class="summary">No passing testbench waveform is available for this module.</p>')
    return "".join(parts)


def render_module(
    module: ModuleDoc,
    root: Path,
    out: Path,
    run_sims: bool,
    strict: bool,
    stop_time: str,
    sim_cache: dict[str, dict[str, Any]],
) -> None:
    module_dir = out / "modules" / module_doc_slug(module)
    module_dir.mkdir(parents=True, exist_ok=True)
    version = docs_version(out)
    body = f"""
<header><div class="wrap">
  <nav class="breadcrumb"><a href="../../index.html">RadHDL</a> / <a href="../../libraries/{html.escape(module.library)}.html">{html.escape(module.library)}</a></nav>
  <div class="kicker">{html.escape(module.category)} / {html.escape(module.kind)}</div>
  <h1>{html.escape(module.name)}</h1>
  <div class="meta">Documentation version: {html.escape(version)} / Package: {html.escape(package_group(module))} / Source package: {html.escape(source_package_group(module))}</div>
  <div class="summary">{paragraph(module.description, "No source description has been written for this module yet.")}</div>
  {render_module_quick_links(module)}
</div></header>
<main class="wrap">
  <h2>Use Cases</h2>
  <ul>{''.join(f'<li>{html.escape(item)}</li>' for item in use_cases(module))}</ul>
  <h2>Block Diagram</h2>
  <div class="diagram">{render_block_svg(module)}</div>
  {render_integration_template(module)}
  {field_table("Generics", module.generics, include_direction=False)}
  {field_table("Ports", ordered_ports_for_docs(module.ports), include_direction=True)}
  {render_register_interfaces(module)}
  {render_register_maps(module)}
  {render_testbenches(module, root, out, run_sims, strict, stop_time, sim_cache)}
  <h2>Sources</h2>
  <ul>{''.join(f'<li>{html.escape(source)}</li>' for source in module.sources)}</ul>
</main>
<footer><div class="wrap">RadHDL documentation version {html.escape(version)} / Generated by radhdl-docgen {VERSION}</div></footer>
"""
    (module_dir / "index.html").write_text(page(f"{module.name} Datasheet", body, depth=2), encoding="utf-8")


def render_library_pages(modules: list[ModuleDoc], out: Path) -> None:
    lib_dir = out / "libraries"
    lib_dir.mkdir(parents=True, exist_ok=True)
    libraries = sorted({module.library for module in modules})
    version = docs_version(out)
    for library in libraries:
        library_modules = sorted((module for module in modules if module.library == library), key=lambda item: item.name.lower())
        categories = sorted({module.category for module in library_modules})
        sections = []
        for category in categories:
            cards = []
            for module in [item for item in library_modules if item.category == category]:
                desc = module.description.splitlines()[0] if module.description else "Datasheet generated from VHDL source."
                cards.append(
                    f'<div class="card"><strong><a href="../modules/{module_doc_slug(module)}/index.html">{html.escape(module.name)}</a></strong>'
                    f'<div class="meta">{html.escape(module.kind)} / {len(module.ports)} ports / {len(module.generics)} generics</div>'
                    f'<p>{html.escape(desc)}</p></div>'
                )
            sections.append(f"<h2>{html.escape(category)}</h2><div class=\"grid\">{''.join(cards)}</div>")
        body = f"""
<header><div class="wrap">
  <nav class="breadcrumb"><a href="../index.html">RadHDL</a> / Library</nav>
  <div class="kicker">Library Index</div>
  <h1>{html.escape(library)}</h1>
  <div class="meta">Documentation version: {html.escape(version)}</div>
  <p class="summary">This page indexes module datasheets in the {html.escape(library)} library. Library pages are navigation and release grouping pages; implementation detail lives in the module datasheets.</p>
</div></header>
<main class="wrap">{''.join(sections)}</main>
<footer><div class="wrap">RadHDL documentation version {html.escape(version)} / Generated by radhdl-docgen {VERSION}</div></footer>
"""
        (lib_dir / f"{library}.html").write_text(page(f"{library} Library", body, depth=1), encoding="utf-8")


def render_datasheet_browser(modules: list[ModuleDoc]) -> str:
    preferred_categories = ["DSP", "Debug", "Interfaces"]
    discovered = sorted({module.category for module in modules if module.category not in preferred_categories})
    categories = [category for category in preferred_categories if any(module.category == category for module in modules)] + discovered
    package_order = {"Transform": 0, "Matrix": 1, "Filter": 2, "Detection": 3, "Misc": 4}
    sections: list[str] = []
    for category in categories:
        category_modules = [module for module in modules if module.category == category]
        packages = sorted({package_group(module) for module in category_modules}, key=lambda item: (package_order.get(item, 100), item.lower()))
        package_sections: list[str] = []
        for package in packages:
            package_modules = sorted(
                [module for module in category_modules if package_group(module) == package],
                key=lambda item: item.name.lower(),
            )
            rows = []
            for module in package_modules:
                regs = register_count(module)
                register_meta = f" / {regs} registers" if regs else ""
                search_text = " ".join(
                    [
                        module.name,
                        module.library,
                        module.category,
                        package,
                        source_package_group(module),
                        module.description.splitlines()[0] if module.description else "",
                        register_search_text(module),
                    ]
                ).lower()
                rows.append(
                    '<div class="datasheet-link-row" '
                    f'data-datasheet-item data-search="{html.escape(search_text)}">'
                    f'<a href="modules/{module_doc_slug(module)}/index.html">{html.escape(module.name)}</a>'
                    f'<span class="meta">{html.escape(source_package_group(module))} / {len(module.ports)} ports / {len(module.generics)} generics{html.escape(register_meta)}</span>'
                    "</div>"
                )
            package_sections.append(
                f'<details class="package-group" data-package-group>'
                f'<summary>{html.escape(package)} <span class="meta">{len(package_modules)} datasheets</span></summary>'
                f'<div class="datasheet-list">{"".join(rows)}</div>'
                "</details>"
            )
        sections.append(
            f'<details class="datasheet-section" data-datasheet-section>'
            f'<summary>{html.escape(category)} <span class="meta">{len(category_modules)} datasheets</span></summary>'
            f'{"".join(package_sections)}'
            "</details>"
        )
    script = """
<script>
(() => {
  const input = document.querySelector("[data-datasheet-search]");
  if (!input) return;
  const apply = () => {
    const query = input.value.trim().toLowerCase();
    document.querySelectorAll("[data-datasheet-item]").forEach((row) => {
      row.hidden = query && !row.dataset.search.includes(query);
    });
    document.querySelectorAll("[data-package-group]").forEach((group) => {
      group.hidden = !group.querySelector("[data-datasheet-item]:not([hidden])");
      if (query && !group.hidden) group.open = true;
    });
    document.querySelectorAll("[data-datasheet-section]").forEach((section) => {
      section.hidden = !section.querySelector("[data-package-group]:not([hidden])");
      if (query && !section.hidden) section.open = true;
    });
  };
  input.addEventListener("input", apply);
})();
</script>
""".strip()
    return (
        '<section class="datasheet-browser">'
        '<input class="datasheet-search" type="search" data-datasheet-search placeholder="Search datasheets">'
        f'{"".join(sections)}'
        f"{script}"
        "</section>"
    )


def render_register_index(modules: list[ModuleDoc]) -> str:
    register_modules = sorted(
        [module for module in modules if module.register_maps],
        key=lambda item: (item.category.lower(), package_group(item).lower(), item.name.lower()),
    )
    if not register_modules:
        return '<p class="summary">No module datasheets currently declare register maps.</p>'
    rows = []
    for module in register_modules:
        map_names = ", ".join(regmap.name for regmap in module.register_maps)
        regs = register_count(module)
        search_text = " ".join(
            [
                module.name,
                module.library,
                module.category,
                package_group(module),
                source_package_group(module),
                map_names,
                register_search_text(module),
            ]
        ).lower()
        rows.append(
            '<div class="datasheet-link-row" '
            f'data-register-item data-search="{html.escape(search_text)}">'
            f'<a href="modules/{module_doc_slug(module)}/index.html#register-maps">{html.escape(module.name)}</a>'
            f'<span class="meta">{html.escape(package_group(module))} / {html.escape(map_names)} / {regs} registers</span>'
            "</div>"
        )
    script = """
<script>
(() => {
  const input = document.querySelector("[data-register-search]");
  if (!input) return;
  const apply = () => {
    const query = input.value.trim().toLowerCase();
    document.querySelectorAll("[data-register-item]").forEach((row) => {
      row.hidden = query && !row.dataset.search.includes(query);
    });
  };
  input.addEventListener("input", apply);
})();
</script>
""".strip()
    return (
        '<section class="datasheet-browser register-index">'
        '<input class="datasheet-search" type="search" data-register-search placeholder="Search register-map datasheets">'
        f'<div class="datasheet-list">{"".join(rows)}</div>'
        f"{script}"
        "</section>"
    )


def render_index(modules: list[ModuleDoc], benches: list[TestbenchDoc], maps: list[RegisterMapDoc], out: Path, root: Path) -> None:
    version = docs_version(out)
    body = f"""
<header><div class="wrap">
  <div class="kicker">RadHDL Documentation</div>
  <h1>RadHDL Datasheets</h1>
  <div class="meta">Documentation version: {html.escape(version)}</div>
  <p class="summary">Static HDL documentation for RadHDL modules. Datasheets include ports, generics, instantiation templates, register maps, testbench links, and optional GHDL waveform previews.</p>
</div></header>
<main class="wrap">
  <h2>Catalog Summary</h2>
  <table><tbody>
    <tr><th>Version</th><td>{html.escape(version)}</td></tr>
    <tr><th>Datasheets</th><td>{len(modules)}</td></tr>
    <tr><th>Testbenches</th><td>{len(benches)}</td></tr>
    <tr><th>Register maps</th><td>{len(maps)}</td></tr>
  </tbody></table>
  <h2>Register Map Datasheets</h2>
  {render_register_index(modules)}
  <h2>Datasheets</h2>
  {render_datasheet_browser(modules)}
</main>
<footer><div class="wrap">RadHDL documentation version {html.escape(version)} / Generated by radhdl-docgen {VERSION}</div></footer>
"""
    (out / "index.html").write_text(page("RadHDL Datasheets", body), encoding="utf-8")


def build_docs(args: argparse.Namespace) -> int:
    root = args.radhdl.expanduser().resolve()
    out = args.out.expanduser().resolve()
    if not root.exists():
        raise FileNotFoundError(f"RadHDL path not found: {root}")
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    write_css(out, args.theme)
    hdl_units, benches, maps = catalog(root)
    modules = datasheet_modules(hdl_units)
    sim_cache: dict[str, dict[str, Any]] = {}
    for module in modules:
        render_module(module, root, out, args.run_sims, args.strict, args.stop_time, sim_cache)
    render_library_pages(modules, out)
    render_index(modules, benches, maps, out, root)
    (out / "catalog.json").write_text(
        json.dumps(
            {
                "schema": "radhdl-docgen-catalog",
                "version": VERSION,
                "radhdl": root.name,
                "modules": [asdict(module) for module in modules],
                "hdl_units": [asdict(module) for module in hdl_units],
                "testbenches": [asdict(bench) for bench in benches],
                "register_maps": [asdict(regmap) for regmap in maps],
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"Generated {len(modules)} RadHDL datasheets at {out}")
    return 0


def build_one_module(args: argparse.Namespace) -> int:
    root = args.radhdl.expanduser().resolve()
    out = args.out.expanduser().resolve()
    modules, _benches, _maps = catalog(root)
    modules = datasheet_modules(modules)
    module = next((item for item in modules if item.name == args.name), None)
    if module is None:
        raise ValueError(f"module not found: {args.name}")
    out.mkdir(parents=True, exist_ok=True)
    write_css(out, args.theme)
    render_module(module, root, out, args.run_sims, args.strict, args.stop_time, {})
    print(out / "modules" / module_doc_slug(module) / "index.html")
    return 0


def run_one_sim(args: argparse.Namespace) -> int:
    root = args.radhdl.expanduser().resolve()
    out = args.out.expanduser().resolve()
    benches = discover_testbenches(root)
    bench = next((item for item in benches if item.name == args.testbench), None)
    if bench is None:
        raise ValueError(f"testbench not found: {args.testbench}")
    status = run_ghdl(bench, root, out, args.strict, args.stop_time)
    print(json.dumps(status, indent=2))
    return 0 if status.get("status") in {"passed", "skipped"} else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate RadHDL datasheet-style documentation.")
    parser.add_argument("--version", action="version", version=f"radhdl-docgen {VERSION}")
    sub = parser.add_subparsers(dest="command", required=True)

    catalog_parser = sub.add_parser("catalog", help="Emit machine-readable RadHDL documentation catalog.")
    catalog_parser.add_argument("--radhdl", type=Path, default=Path.cwd())
    catalog_parser.add_argument("--json", action="store_true", default=True)

    build_parser_ = sub.add_parser("build", help="Generate a static HTML documentation site.")
    build_parser_.add_argument("--radhdl", type=Path, default=Path.cwd())
    build_parser_.add_argument("--out", type=Path, required=True)
    build_parser_.add_argument("--run-sims", action="store_true", help="Run associated testbenches with GHDL when available.")
    build_parser_.add_argument("--strict", action="store_true", help="Fail on simulation/tool errors instead of recording skips.")
    build_parser_.add_argument("--stop-time", default="100us", help="GHDL --stop-time used for generated waveform runs.")
    build_parser_.add_argument("--theme", choices=("dark", "light", "auto"), default="dark", help="Static HTML color theme.")

    module_parser = sub.add_parser("module", help="Generate one module datasheet.")
    module_parser.add_argument("name")
    module_parser.add_argument("--radhdl", type=Path, default=Path.cwd())
    module_parser.add_argument("--out", type=Path, required=True)
    module_parser.add_argument("--run-sims", action="store_true")
    module_parser.add_argument("--strict", action="store_true")
    module_parser.add_argument("--stop-time", default="100us")
    module_parser.add_argument("--theme", choices=("dark", "light", "auto"), default="dark")

    sim_parser = sub.add_parser("sim", help="Run one testbench and capture waveform status.")
    sim_parser.add_argument("testbench")
    sim_parser.add_argument("--radhdl", type=Path, default=Path.cwd())
    sim_parser.add_argument("--out", type=Path, required=True)
    sim_parser.add_argument("--strict", action="store_true")
    sim_parser.add_argument("--stop-time", default="100us")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "catalog":
        print(json.dumps(json_catalog(args.radhdl.expanduser().resolve()), indent=2))
        return 0
    if args.command == "build":
        return build_docs(args)
    if args.command == "module":
        return build_one_module(args)
    if args.command == "sim":
        return run_one_sim(args)
    parser.print_help()
    return 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
