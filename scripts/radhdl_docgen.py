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
VENDOR_SIM_LIBRARIES = {"xpm", "unisim", "unimacro", "unisims_ver"}
GHDL_BASE_ARGS = ["--std=08", "--ieee=synopsys"]
EXCLUDED_PARTS = {
    ".git",
    ".Xil",
    ".srcs",
    "__pycache__",
    "build",
    "dist",
    "release",
    "sim",
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
    for candidate in ("raddsp", "radif", "radila"):
        if candidate in parts:
            return candidate
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
        for match in ENTITY_RE.finditer(text):
            name = match.group(1)
            if name.lower().startswith("tb_") or "testbench" in rel.lower() or "testbenches" in rel.lower():
                benches.append(TestbenchDoc(name=name, path=rel))
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
        fields.append({"name": match.group(4).strip(), "msb": msb, "lsb": lsb})
    return fields


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
    if explicit:
        return explicit
    raw_name = str(register.get("name", "register")).split(".")[-1]
    friendly = raw_name.replace("_", " ").strip()
    lower = raw_name.lower()
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
        fields=parse_bit_fields(description),
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
            maps.append(
                RegisterMapDoc(
                    name=region_name,
                    path=rel_path(path, root),
                    base=hex_string(region.get("base", "")),
                    description=str(region.get("description") or data.get("description") or ""),
                    data_width=default_width,
                    registers=registers,
                )
            )
    return maps


def attach_register_maps(modules: list[ModuleDoc], maps: list[RegisterMapDoc]) -> None:
    by_name = {module.name.lower(): module for module in modules}
    for regmap in maps:
        haystack = f"{regmap.name} {regmap.path}".lower()
        attached = False
        for name, module in by_name.items():
            if name in haystack:
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
    return modules, benches, maps


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
table {{ width: 100%; border-collapse: collapse; margin: 12px 0 18px; font-size: 14px; }}
th, td {{ border: 1px solid var(--line); padding: 8px 10px; vertical-align: top; text-align: left; }}
th {{ background: var(--panel); font-weight: 700; }}
code, pre {{ font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }}
pre {{ overflow: auto; padding: 14px; border-radius: 6px; background: var(--code); color: #f4f7fb; }}
.diagram {{ overflow-x: auto; padding: 12px 0; }}
.reg-card {{ border: 1px solid var(--line); border-radius: 6px; padding: 12px; margin: 12px 0; background: var(--card); }}
.reg-card h4 {{ margin: 0 0 6px; }}
.reg-meta {{ color: var(--muted); font-size: 13px; margin-bottom: 8px; }}
.reg-ruler, .reg-bits {{ display: grid; grid-template-columns: repeat(32, minmax(18px, 1fr)); }}
.reg-ruler span {{ font-size: 10px; color: var(--muted); text-align: center; border: 1px solid var(--line); border-bottom: 0; padding: 2px 0; background: var(--ruler); }}
.reg-field {{ min-height: 38px; border: 1px solid var(--line); padding: 4px 6px; font-size: 12px; background: var(--soft); overflow-wrap: anywhere; }}
.reg-field.reserved {{ color: var(--muted); background: var(--reserved); }}
.status {{ border-left: 4px solid #d59b35; background: var(--panel); padding: 10px 12px; margin: 10px 0; }}
.wave {{ width: 100%; overflow-x: auto; border: 1px solid var(--line); border-radius: 6px; padding: 10px; background: var(--soft); }}
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
</body>
</html>
"""


def paragraph(text: str, fallback: str = "") -> str:
    value = (text or fallback).strip()
    if not value:
        return ""
    return "".join(f"<p>{html.escape(part.strip())}</p>" for part in value.split("\n\n") if part.strip())


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


def render_block_svg(module: ModuleDoc) -> str:
    left = [port for port in module.ports if port.direction in {"in", "inout"}]
    right = [port for port in module.ports if port.direction in {"out", "buffer", "inout"}]
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
        '<style>text{font-family:Inter,Arial,sans-serif;font-size:13px;fill:#111827}.pin{stroke:#106b62;stroke-width:2;fill:none}.box{fill:#f7f9fc;stroke:#26323f;stroke-width:2}.bubble{fill:#fff;stroke:#106b62;stroke-width:2}.clock{fill:none;stroke:#106b62;stroke-width:2}</style>',
        f'<rect class="box" x="{rect_x}" y="{rect_y}" width="{rect_w}" height="{rect_h}" rx="4"/>',
        f'<text x="{rect_x + rect_w / 2}" y="{rect_y + 34}" text-anchor="middle" font-weight="700">{html.escape(module.name)}</text>',
        f'<text x="{rect_x + rect_w / 2}" y="{rect_y + 56}" text-anchor="middle">{html.escape(module.library)} {html.escape(module.kind)}</text>',
    ]
    def is_clock(port: FieldDoc) -> bool:
        name = port.name.lower()
        return name in {"clk", "clock", "aclk"} or name.endswith("_clk") or name.endswith("clk")

    def is_active_low(port: FieldDoc) -> bool:
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
        if is_clock(port):
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
        if is_clock(port):
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
            fields.append({"name": str(field_doc["name"]), "msb": msb, "lsb": lsb, "reserved": False})
    if not fields:
        return [{"name": "value", "msb": width - 1, "lsb": 0, "reserved": False}]
    fields.sort(key=lambda item: item["msb"], reverse=True)
    segments: list[dict[str, Any]] = []
    cursor = width - 1
    for field_doc in fields:
        if field_doc["msb"] < cursor:
            segments.append({"name": "reserved", "msb": cursor, "lsb": field_doc["msb"] + 1, "reserved": True})
        segments.append(field_doc)
        cursor = field_doc["lsb"] - 1
    if cursor >= 0:
        segments.append({"name": "reserved", "msb": cursor, "lsb": 0, "reserved": True})
    return segments


def render_register_block(register: RegisterDoc) -> str:
    width = max(1, min(register.width or 32, 64))
    ruler = "".join(f"<span>{bit}</span>" for bit in range(width - 1, -1, -1))
    fields = []
    for segment in register_segments(register):
        msb = int(segment["msb"])
        lsb = int(segment["lsb"])
        span = msb - lsb + 1
        start = width - msb
        label = segment["name"] if msb == lsb else f"{segment['name']} [{msb}:{lsb}]"
        css = "reg-field reserved" if segment.get("reserved") else "reg-field"
        fields.append(f'<div class="{css}" style="grid-column: {start} / span {span};">{html.escape(label)}</div>')
    return (
        f'<div class="reg-ruler" style="grid-template-columns: repeat({width}, minmax(18px, 1fr));">{ruler}</div>'
        f'<div class="reg-bits" style="grid-template-columns: repeat({width}, minmax(18px, 1fr));">{"".join(fields)}</div>'
    )


def render_register_maps(module: ModuleDoc) -> str:
    if not module.register_maps:
        return ""
    parts = ["<h2>Register Maps</h2>"]
    for regmap in module.register_maps:
        parts.append(f"<h3>{html.escape(regmap.name)}</h3>")
        parts.append(f'<p class="meta">Source: {html.escape(regmap.path)} Base: {html.escape(regmap.base)}</p>')
        parts.append(paragraph(regmap.description))
        if not regmap.registers:
            parts.append('<p class="summary">No registers declared in this map.</p>')
            continue
        rows = []
        for register in regmap.registers:
            rows.append(
                "<tr>"
                f"<td>{html.escape(register.name)}</td>"
                f"<td>{html.escape(register.address)}</td>"
                f"<td>{html.escape(register.offset)}</td>"
                f"<td>{html.escape(register.access)}</td>"
                f"<td>{html.escape(register.reset)}</td>"
                f"<td>{html.escape(register.description)}</td>"
                "</tr>"
            )
        parts.append(
            "<table><thead><tr><th>Register</th><th>Address</th><th>Offset</th><th>Access</th><th>Reset</th><th>Description</th></tr></thead><tbody>"
            + "".join(rows)
            + "</tbody></table>"
        )
        for register in regmap.registers:
            meta_items = [
                item
                for item in [
                    f"Address {register.address}" if register.address else "",
                    f"Offset {register.offset}" if register.offset else "",
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


def source_snippet(module: ModuleDoc, root: Path) -> str:
    source = root / module.path
    if not source.exists():
        return ""
    text = read_text(source)
    entity_match = re.search(rf"entity\s+{re.escape(module.name)}\s+is.*?end(?:\s+entity)?(?:\s+{re.escape(module.name)})?\s*;", text, re.IGNORECASE | re.DOTALL)
    snippet = entity_match.group(0) if entity_match else "\n".join(text.splitlines()[:80])
    return f"<pre><code>{html.escape(snippet)}</code></pre>"


def render_vcd_preview(vcd_path: Path) -> str:
    if not vcd_path.exists():
        return ""
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
            if code in samples and len(samples[code]) < 32:
                samples[code].append((current_time, value))
    rows = []
    seen_names: set[str] = set()
    for code, name in list(signals.items())[:16]:
        if name in seen_names:
            continue
        seen_names.add(name)
        values = " | ".join(f"{time}:{value}" for time, value in samples.get(code, [])[:16])
        rows.append(f"<tr><td>{html.escape(name)}</td><td>{html.escape(values)}</td></tr>")
    if not rows:
        return ""
    return '<div class="wave"><table><thead><tr><th>Signal</th><th>Samples</th></tr></thead><tbody>' + "".join(rows) + "</tbody></table></div>"


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
    return sorted(sources, key=source_priority)


def testbench_work_sources(testbench: Path, root: Path) -> list[Path]:
    sources: list[Path] = []
    for path in sorted(testbench.parent.glob("*.vhd")):
        if path == testbench or should_skip(path, root):
            continue
        text = read_text(path)
        if PACKAGE_RE.search(text):
            sources.append(path)
    sources.append(testbench)
    return sources


def run_ghdl_command(command: list[str], work: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=work, check=True, capture_output=True, text=True)


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
            for library in libraries:
                analyze_sources(ghdl, root, work, library, library_sources(root, library), status)
            analyze_sources(ghdl, root, work, "work", testbench_work_sources(tb_path, root), status)
            run_ghdl_command([ghdl, "-e", *GHDL_BASE_ARGS, f"-P{work}", f"--workdir={work}", testbench.name], work)
            vcd = sim_dir / f"{testbench.name}.vcd"
            completed = run_ghdl_command(
                [ghdl, "-r", *GHDL_BASE_ARGS, f"-P{work}", f"--workdir={work}", testbench.name, f"--vcd={vcd}", f"--stop-time={stop_time}"],
                work,
            )
            status.update(
                {
                    "status": "passed",
                    "vcd": str(vcd),
                    "stdout": completed.stdout[-4000:] if completed.stdout else "",
                    "stderr": completed.stderr[-4000:] if completed.stderr else "",
                }
            )
        except subprocess.CalledProcessError as exc:
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
    parts = ["<h2>Testbenches and Waveforms</h2>"]
    if not module.testbenches:
        parts.append('<p class="summary">No directly associated testbench was found.</p>')
        return "".join(parts)
    rows = []
    for bench in module.testbenches:
        status = bench.simulation
        if run_sims:
            status = sim_cache.get(bench.name)
            if status is None:
                status = run_ghdl(bench, root, out, strict, stop_time)
                sim_cache[bench.name] = status
            bench.simulation = status
        state = status.get("status", "not-run") if status else "not-run"
        artifact_links = []
        status_path = Path("..") / ".." / "simulations" / module_slug(bench.name) / "simulation_status.json"
        if status:
            artifact_links.append(f'<a href="{html.escape(str(status_path))}">status</a>')
        if status.get("vcd"):
            vcd_path = Path("..") / ".." / "simulations" / module_slug(bench.name) / f"{module_slug(bench.name)}.vcd"
            artifact_links.append(f'<a href="{html.escape(str(vcd_path))}">vcd</a>')
        rows.append(
            f"<tr><td>{html.escape(bench.name)}</td><td>{html.escape(bench.path)}</td>"
            f"<td>{html.escape(state)}</td><td>{', '.join(artifact_links) or ''}</td></tr>"
        )
        if state == "skipped":
            parts.append(f'<div class="status">{html.escape(bench.name)} simulation skipped: {html.escape(status.get("reason", ""))}</div>')
        if state == "failed":
            reason = (status.get("stderr") or status.get("stdout") or "").strip().splitlines()
            if not reason and status.get("analysis_skipped"):
                reason = [json.dumps(status["analysis_skipped"])[:300]]
            message = reason[0] if reason else "GHDL simulation failed; see status JSON for details."
            parts.append(f'<div class="status">{html.escape(bench.name)} simulation failed: {html.escape(message)}</div>')
        if status.get("vcd"):
            parts.append(render_vcd_preview(Path(status["vcd"])))
    parts.insert(
        1,
        "<table><thead><tr><th>Testbench</th><th>Source</th><th>Simulation</th><th>Artifacts</th></tr></thead><tbody>"
        + "".join(rows)
        + "</tbody></table>",
    )
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
    module_dir = out / "modules" / module_slug(module.name)
    module_dir.mkdir(parents=True, exist_ok=True)
    body = f"""
<header><div class="wrap">
  <nav class="breadcrumb"><a href="../../index.html">RadHDL</a> / <a href="../../libraries/{html.escape(module.library)}.html">{html.escape(module.library)}</a></nav>
  <div class="kicker">{html.escape(module.category)} / {html.escape(module.kind)}</div>
  <h1>{html.escape(module.name)}</h1>
  <div class="summary">{paragraph(module.description, "No source description has been written for this module yet.")}</div>
</div></header>
<main class="wrap">
  <h2>Use Cases</h2>
  <ul>{''.join(f'<li>{html.escape(item)}</li>' for item in use_cases(module))}</ul>
  <h2>Block Diagram</h2>
  <div class="diagram">{render_block_svg(module)}</div>
  {field_table("Generics", module.generics, include_direction=False)}
  {field_table("Ports", module.ports, include_direction=True)}
  {render_register_maps(module)}
  {render_testbenches(module, root, out, run_sims, strict, stop_time, sim_cache)}
  <h2>HDL Example</h2>
  {source_snippet(module, root)}
  <h2>Sources</h2>
  <ul>{''.join(f'<li>{html.escape(source)}</li>' for source in module.sources)}</ul>
</main>
<footer><div class="wrap">Generated by radhdl-docgen {VERSION}</div></footer>
"""
    (module_dir / "index.html").write_text(page(f"{module.name} Datasheet", body, depth=2), encoding="utf-8")


def render_library_pages(modules: list[ModuleDoc], out: Path) -> None:
    lib_dir = out / "libraries"
    lib_dir.mkdir(parents=True, exist_ok=True)
    libraries = sorted({module.library for module in modules})
    for library in libraries:
        library_modules = sorted((module for module in modules if module.library == library), key=lambda item: item.name.lower())
        categories = sorted({module.category for module in library_modules})
        sections = []
        for category in categories:
            cards = []
            for module in [item for item in library_modules if item.category == category]:
                desc = module.description.splitlines()[0] if module.description else "Datasheet generated from VHDL source."
                cards.append(
                    f'<div class="card"><strong><a href="../modules/{module_slug(module.name)}/index.html">{html.escape(module.name)}</a></strong>'
                    f'<div class="meta">{html.escape(module.kind)} / {len(module.ports)} ports / {len(module.generics)} generics</div>'
                    f'<p>{html.escape(desc)}</p></div>'
                )
            sections.append(f"<h2>{html.escape(category)}</h2><div class=\"grid\">{''.join(cards)}</div>")
        body = f"""
<header><div class="wrap">
  <nav class="breadcrumb"><a href="../index.html">RadHDL</a> / Library</nav>
  <div class="kicker">Library Index</div>
  <h1>{html.escape(library)}</h1>
  <p class="summary">This page indexes module datasheets in the {html.escape(library)} library. Library pages are navigation and release grouping pages; implementation detail lives in the module datasheets.</p>
</div></header>
<main class="wrap">{''.join(sections)}</main>
<footer><div class="wrap">Generated by radhdl-docgen {VERSION}</div></footer>
"""
        (lib_dir / f"{library}.html").write_text(page(f"{library} Library", body, depth=1), encoding="utf-8")


def render_index(modules: list[ModuleDoc], benches: list[TestbenchDoc], maps: list[RegisterMapDoc], out: Path, root: Path) -> None:
    libraries = sorted({module.library for module in modules})
    categories = sorted({module.category for module in modules})
    library_cards = "".join(
        f'<div class="card"><strong><a href="libraries/{html.escape(library)}.html">{html.escape(library)}</a></strong>'
        f'<div class="meta">{sum(1 for module in modules if module.library == library)} datasheets</div></div>'
        for library in libraries
    )
    category_sections = []
    for category in categories:
        cards = []
        for module in sorted([item for item in modules if item.category == category], key=lambda item: item.name.lower()):
            desc = module.description.splitlines()[0] if module.description else "Datasheet generated from VHDL source."
            cards.append(
                f'<div class="card"><strong><a href="modules/{module_slug(module.name)}/index.html">{html.escape(module.name)}</a></strong>'
                f'<div class="meta">{html.escape(module.library)} / {html.escape(module.kind)}</div><p>{html.escape(desc)}</p></div>'
            )
        category_sections.append(f"<h2>{html.escape(category)}</h2><div class=\"grid\">{''.join(cards)}</div>")
    body = f"""
<header><div class="wrap">
  <div class="kicker">RadHDL Documentation</div>
  <h1>RadHDL Datasheets</h1>
  <p class="summary">Static HDL documentation generated from {html.escape(str(root))}. Module pages are datasheet-style references with ports, generics, source snippets, register maps, testbench links, and optional GHDL waveform previews.</p>
</div></header>
<main class="wrap">
  <h2>Libraries</h2>
  <div class="grid">{library_cards}</div>
  <h2>Catalog Summary</h2>
  <table><tbody>
    <tr><th>Modules and packages</th><td>{len(modules)}</td></tr>
    <tr><th>Testbenches</th><td>{len(benches)}</td></tr>
    <tr><th>Register maps</th><td>{len(maps)}</td></tr>
  </tbody></table>
  {''.join(category_sections)}
</main>
<footer><div class="wrap">Generated by radhdl-docgen {VERSION}</div></footer>
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
    modules, benches, maps = catalog(root)
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
                "radhdl": str(root),
                "modules": [asdict(module) for module in modules],
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
    module = next((item for item in modules if item.name == args.name), None)
    if module is None:
        raise ValueError(f"module not found: {args.name}")
    out.mkdir(parents=True, exist_ok=True)
    write_css(out, args.theme)
    render_module(module, root, out, args.run_sims, args.strict, args.stop_time, {})
    print(out / "modules" / module_slug(module.name) / "index.html")
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
