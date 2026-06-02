#!/usr/bin/env python3
import argparse
import html
import json
import socket
import struct
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path


def parse_lanes(specs):
    lanes = []
    bit = 0
    for spec in specs:
        parts = spec.split(":")
        signed = False
        if parts and parts[-1] in ("s", "signed"):
            signed = True
            parts = parts[:-1]
        if len(parts) == 2:
            name, width_s = parts
            width = int(width_s, 0)
            lo = bit
            hi = bit + width - 1
            bit += width
        elif len(parts) == 3:
            name, hi_s, lo_s = parts
            hi = int(hi_s, 0)
            lo = int(lo_s, 0)
        else:
            raise SystemExit(f"bad lane '{spec}', use name:width[:signed] or name:hi:lo[:signed]")
        if hi < lo or hi > 63 or lo < 0:
            raise SystemExit(f"bad lane range '{spec}'")
        lanes.append({"name": name, "hi": hi, "lo": lo, "signed": signed})
    return lanes or [{"name": "word", "hi": 31, "lo": 0}]


def load_words(path):
    data = Path(path).read_bytes()
    count = len(data) // 4
    return list(struct.unpack("<" + "I" * count, data[: count * 4]))


def load_samples(path, sample_words):
    words = load_words(path)
    samples = []
    for i in range(0, len(words), sample_words):
        value = 0
        for j, word in enumerate(words[i:i + sample_words]):
            value |= word << (32 * j)
        samples.append(value)
    return samples


def receive(path, host, port):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind((host, port))
        srv.listen(1)
        conn, _ = srv.accept()
        with conn, path.open("wb") as fp:
            while True:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                fp.write(chunk)


def render_html(samples, lanes, title, source_name):
    sample_bits = max(32, max((sample.bit_length() for sample in samples), default=0))
    sample_digits = max(8, (sample_bits + 3) // 4)
    samples_json = json.dumps([f"0x{sample:0{sample_digits}x}" for sample in samples])
    lanes_json = json.dumps(lanes)
    return f"""<!doctype html>
<meta charset="utf-8">
<title>{html.escape(title)}</title>
<style>
body {{ margin: 0; font: 13px system-ui, sans-serif; color: #16202a; background: #f5f7fa; }}
header {{ display: flex; gap: 16px; align-items: center; padding: 12px 16px; background: #fff; border-bottom: 1px solid #d8dde6; position: sticky; top: 0; z-index: 3; }}
a {{ color: #0f5f9f; text-decoration: none; }}
button, input, select {{ font: inherit; }}
button {{ border: 1px solid #b9c4d0; background: #fff; border-radius: 4px; padding: 4px 8px; cursor: pointer; }}
input, select {{ border: 1px solid #b9c4d0; border-radius: 4px; padding: 3px 6px; background: #fff; }}
input {{ width: 78px; }}
.meta {{ color: #586575; }}
.controls {{ display: flex; flex-wrap: wrap; gap: 8px 10px; align-items: center; padding: 10px 14px; background: #eef3f8; border-bottom: 1px solid #d8dde6; position: sticky; top: 45px; z-index: 2; }}
.lane-controls {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); gap: 8px; padding: 10px 14px; background: #fff; border-bottom: 1px solid #d8dde6; }}
.lane-control {{ display: flex; align-items: center; gap: 8px; min-width: 0; }}
.lane-control[data-mode="digital"] .draw-select {{ display: none; }}
.lane-name {{ font-family: ui-monospace, SFMono-Regular, Menlo, monospace; min-width: 96px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }}
.wrap {{ overflow: auto; margin: 14px; border: 1px solid #cfd7e3; background: #fff; }}
svg {{ display: block; }}
.label {{ fill: #1f2a37; font-size: 12px; }}
.range {{ fill: #64748b; font-size: 11px; text-anchor: end; }}
.wave {{ fill: none; stroke: #087f5b; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }}
.dot {{ fill: #087f5b; stroke: none; }}
.zero {{ stroke: #cbd5e1; stroke-width: 1; stroke-dasharray: 3 3; }}
.grid {{ stroke: #edf1f5; stroke-width: 1; }}
.cursor {{ stroke: #c2410c; stroke-width: 1.5; pointer-events: none; }}
.tick {{ stroke: #94a3b8; stroke-width: 1; }}
#readout {{ white-space: pre; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; overflow: hidden; text-overflow: ellipsis; }}
</style>
<header>
  <a href="/index.html">captures</a>
  <strong>{html.escape(title)}</strong>
  <span class="meta">{len(samples)} samples from {html.escape(source_name)}</span>
  <span id="readout">move over waveform</span>
</header>
<div class="controls">
  <label>start <input id="start" type="number" min="0" value="0"></label>
  <label>end <input id="end" type="number" min="0" value="{max(0, len(samples) - 1)}"></label>
  <button id="apply">Apply window</button>
  <button id="first500">First 500</button>
  <button id="reset">Reset</button>
  <button id="prev">Prev</button>
  <button id="next">Next</button>
  <button id="zoomIn">Zoom in</button>
  <button id="zoomOut">Zoom out</button>
</div>
<div id="laneControls" class="lane-controls"></div>
<div class="wrap">
<svg id="wave"></svg>
</div>
<script>
const samples = {samples_json};
const lanes = {lanes_json};
const svg = document.getElementById('wave');
const readout = document.getElementById('readout');
const laneControls = document.getElementById('laneControls');
const startInput = document.getElementById('start');
const endInput = document.getElementById('end');
const lanePrefs = lanes.map(l => ({{
  mode: (l.hi - l.lo + 1) === 1 ? 'digital' : 'analog',
  radix: l.signed ? 'signed' : 'unsigned',
  draw: 'smooth'
}}));
function hex(v, bits) {{
  const n = Math.max(1, Math.ceil(bits / 4));
  return '0x' + BigInt(v).toString(16).padStart(n, '0');
}}
function esc(s) {{
  return String(s).replace(/[&<>"]/g, c => ({{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}}[c]));
}}
function clampWindow() {{
  let start = Number(startInput.value);
  let end = Number(endInput.value);
  if (!Number.isFinite(start)) start = 0;
  if (!Number.isFinite(end)) end = samples.length - 1;
  start = Math.max(0, Math.min(samples.length - 1, Math.floor(start)));
  end = Math.max(0, Math.min(samples.length - 1, Math.floor(end)));
  if (end < start) [start, end] = [end, start];
  startInput.value = start;
  endInput.value = end;
  return {{start, end}};
}}
function rawLane(sample, lane) {{
  const width = BigInt(lane.hi - lane.lo + 1);
  const mask = (1n << width) - 1n;
  return (sample >> BigInt(lane.lo)) & mask;
}}
function laneValue(sample, lane, radix) {{
  const width = BigInt(lane.hi - lane.lo + 1);
  const raw = rawLane(sample, lane);
  if (radix === 'signed' && width > 1n && (raw & (1n << (width - 1n)))) {{
    return raw - (1n << width);
  }}
  return raw;
}}
function shownValue(sample, lane, radix) {{
  const width = BigInt(lane.hi - lane.lo + 1);
  const raw = rawLane(sample, lane);
  if (radix === 'hex') return hex(raw, Number(width));
  if (radix === 'signed') return String(laneValue(sample, lane, radix));
  return String(raw);
}}
function pathDigital(values, y, xStep) {{
  const parts = [];
  let last = null;
  let xLast = 150;
  values.forEach((value, i) => {{
    const high = value !== 0n;
    const x = 150 + i * xStep;
    const yv = y + (high ? 0 : 22);
    if (last === null) parts.push(`M${{x}},${{yv}}`);
    else if (high !== last) parts.push(`L${{x}},${{y + (last ? 0 : 22)}} L${{x}},${{yv}}`);
    xLast = x;
    last = high;
  }});
  if (last !== null) parts.push(`L${{xLast + xStep}},${{y + (last ? 0 : 22)}}`);
  return parts.join(' ');
}}
function analogPoints(values, y, xStep) {{
  if (!values.length) return {{path: '', min: 0n, max: 0n}};
  let min = values[0], max = values[0];
  values.forEach(v => {{ if (v < min) min = v; if (v > max) max = v; }});
  let span = max - min;
  if (span === 0n) span = 1n;
  const bottom = y + 58;
  const points = values.map((v, i) => {{
    const x = 150 + i * xStep;
    const frac = Number(v - min) / Number(span);
    const yv = bottom - frac * 58;
    return {{x, y: yv}};
  }});
  return {{points, min, max}};
}}
function pathAnalog(points, draw) {{
  if (!points.length) return '';
  if (draw === 'points') return '';
  if (draw === 'line' || points.length < 3) {{
    return points.map((p, i) => `${{i ? 'L' : 'M'}}${{p.x}},${{p.y.toFixed(2)}}`).join(' ');
  }}
  const interp = [];
  const subdivisions = 6;
  for (let i = 0; i < points.length - 1; i++) {{
    const p0 = points[Math.max(0, i - 1)];
    const p1 = points[i];
    const p2 = points[i + 1];
    const p3 = points[Math.min(points.length - 1, i + 2)];
    for (let s = 0; s < subdivisions; s++) {{
      const t = s / subdivisions;
      const t2 = t * t;
      const t3 = t2 * t;
      const x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3);
      const y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3);
      interp.push({{x, y}});
    }}
  }}
  interp.push(points[points.length - 1]);
  const parts = [`M${{interp[0].x.toFixed(2)}},${{interp[0].y.toFixed(2)}}`];
  for (let i = 1; i < interp.length; i++) {{
    parts.push(`L${{interp[i].x.toFixed(2)}},${{interp[i].y.toFixed(2)}}`);
  }}
  return parts.join(' ');
}}
function rebuildControls() {{
  laneControls.innerHTML = lanes.map((l, i) => `
    <div class="lane-control">
      <span class="lane-name">${{esc(l.name)}} [${{l.hi}}:${{l.lo}}]</span>
      <select data-lane="${{i}}" data-kind="mode">
        <option value="analog" ${{lanePrefs[i].mode === 'analog' ? 'selected' : ''}}>analog</option>
        <option value="digital" ${{lanePrefs[i].mode === 'digital' ? 'selected' : ''}}>digital</option>
      </select>
      <select data-lane="${{i}}" data-kind="radix">
        <option value="signed" ${{lanePrefs[i].radix === 'signed' ? 'selected' : ''}}>signed</option>
        <option value="unsigned" ${{lanePrefs[i].radix === 'unsigned' ? 'selected' : ''}}>unsigned</option>
        <option value="hex" ${{lanePrefs[i].radix === 'hex' ? 'selected' : ''}}>hex</option>
      </select>
      <select class="draw-select" data-lane="${{i}}" data-kind="draw" title="Analog draw style">
        <option value="smooth" ${{lanePrefs[i].draw === 'smooth' ? 'selected' : ''}}>smooth</option>
        <option value="line" ${{lanePrefs[i].draw === 'line' ? 'selected' : ''}}>line</option>
        <option value="points" ${{lanePrefs[i].draw === 'points' ? 'selected' : ''}}>points</option>
      </select>
    </div>`).join('');
  laneControls.querySelectorAll('.lane-control').forEach((row, i) => {{
    row.dataset.mode = lanePrefs[i].mode;
  }});
}}
function render() {{
  const {{start, end}} = clampWindow();
  const count = end - start + 1;
  const xStep = count > 700 ? 2 : count > 350 ? 4 : count > 150 ? 6 : 10;
  const width = Math.max(1100, 150 + count * xStep + 110);
  const height = 74 + lanes.length * 86;
  const grid = [];
  const gridEvery = Math.max(1, Math.ceil(count / 50));
  for (let i = 0; i < count; i += gridEvery) {{
    const x = 150 + i * xStep;
    grid.push(`<line x1="${{x}}" y1="34" x2="${{x}}" y2="${{height - 16}}" class="grid"/>`);
    grid.push(`<text x="${{x + 2}}" y="44" class="range">${{start + i}}</text>`);
  }}
  const rows = [];
  lanes.forEach((lane, laneIndex) => {{
    const pref = lanePrefs[laneIndex];
    const y = 62 + laneIndex * 86;
    const slice = samples.slice(start, end + 1).map(s => laneValue(BigInt(s), lane, pref.radix));
    rows.push(`<text x="12" y="${{y + 16}}" class="label">${{esc(lane.name)}} [${{lane.hi}}:${{lane.lo}}] ${{pref.mode}}/${{pref.radix}}</text>`);
    if (pref.mode === 'digital') {{
      rows.push(`<path d="${{pathDigital(slice, y + 22, xStep)}}" class="wave"/>`);
    }} else {{
      const analog = analogPoints(slice, y + 6, xStep);
      rows.push(`<line x1="150" y1="${{y + 35}}" x2="${{width - 60}}" y2="${{y + 35}}" class="zero"/>`);
      rows.push(`<text x="${{width - 16}}" y="${{y + 12}}" class="range">${{analog.max}}</text>`);
      rows.push(`<text x="${{width - 16}}" y="${{y + 64}}" class="range">${{analog.min}}</text>`);
      rows.push(`<path d="${{pathAnalog(analog.points, pref.draw)}}" class="wave"/>`);
      if (pref.draw === 'points') {{
        rows.push(analog.points.map(p => `<circle cx="${{p.x}}" cy="${{p.y.toFixed(2)}}" r="2.3" class="dot"/>`).join(''));
      }}
    }}
  }});
  svg.setAttribute('width', width);
  svg.setAttribute('height', height);
  svg.setAttribute('viewBox', `0 0 ${{width}} ${{height}}`);
  svg.innerHTML = `${{grid.join('')}}${{rows.join('')}}<line id="cursor" x1="150" y1="30" x2="150" y2="${{height - 10}}" class="cursor" visibility="hidden"/>`;
}}
function sampleIndexFromEvent(ev) {{
  const pt = svg.createSVGPoint();
  pt.x = ev.clientX; pt.y = ev.clientY;
  const p = pt.matrixTransform(svg.getScreenCTM().inverse());
  const {{start, end}} = clampWindow();
  const count = end - start + 1;
  const xStep = count > 700 ? 2 : count > 350 ? 4 : count > 150 ? 6 : 10;
  let idx = start + Math.round((p.x - 150) / xStep);
  idx = Math.max(start, Math.min(end, idx));
  return {{idx, x: 150 + (idx - start) * xStep}};
}}
svg.addEventListener('mousemove', (ev) => {{
  const {{idx, x}} = sampleIndexFromEvent(ev);
  const cursor = document.getElementById('cursor');
  cursor.setAttribute('x1', x); cursor.setAttribute('x2', x);
  cursor.setAttribute('visibility', 'visible');
  const sample = BigInt(samples[idx]);
  const parts = lanes.map((l, i) => `${{l.name}}=${{shownValue(sample, l, lanePrefs[i].radix)}}`);
  readout.textContent = `clk ${{idx}}  sample=${{idx}}  raw=${{hex(sample, 64)}}  ${{parts.join('  ')}}`;
}});
svg.addEventListener('mouseleave', () => {{
  const cursor = document.getElementById('cursor');
  if (cursor) cursor.setAttribute('visibility', 'hidden');
}});
laneControls.addEventListener('change', ev => {{
  const lane = Number(ev.target.dataset.lane);
  const kind = ev.target.dataset.kind;
  if (Number.isFinite(lane) && kind) {{
    lanePrefs[lane][kind] = ev.target.value;
    render();
  }}
}});
document.getElementById('apply').addEventListener('click', render);
document.getElementById('first500').addEventListener('click', () => {{ startInput.value = 0; endInput.value = Math.min(499, samples.length - 1); render(); }});
document.getElementById('reset').addEventListener('click', () => {{ startInput.value = 0; endInput.value = samples.length - 1; render(); }});
function shiftWindow(dir) {{
  const {{start, end}} = clampWindow();
  const span = end - start + 1;
  startInput.value = Math.max(0, Math.min(samples.length - span, start + dir * span));
  endInput.value = Number(startInput.value) + span - 1;
  render();
}}
function zoom(factor) {{
  const {{start, end}} = clampWindow();
  const span = end - start + 1;
  const center = Math.round((start + end) / 2);
  const nextSpan = Math.max(8, Math.min(samples.length, Math.round(span * factor)));
  let nextStart = Math.max(0, center - Math.floor(nextSpan / 2));
  if (nextStart + nextSpan > samples.length) nextStart = samples.length - nextSpan;
  startInput.value = nextStart;
  endInput.value = nextStart + nextSpan - 1;
  render();
}}
document.getElementById('prev').addEventListener('click', () => shiftWindow(-1));
document.getElementById('next').addEventListener('click', () => shiftWindow(1));
document.getElementById('zoomIn').addEventListener('click', () => zoom(0.5));
document.getElementById('zoomOut').addEventListener('click', () => zoom(2));
rebuildControls();
render();
</script>
"""


def render_index(capture_dir):
    capture_dir = Path(capture_dir)
    links = []
    for path in sorted(capture_dir.rglob("*.html")):
        if path.name == "index.html":
            continue
        rel = path.relative_to(capture_dir).as_posix()
        links.append(f'<li><a href="{html.escape(rel)}">{html.escape(rel)}</a></li>')
    return f"""<!doctype html>
<meta charset="utf-8">
<title>RadILA Captures</title>
<style>
body {{ font: 14px system-ui, sans-serif; margin: 24px; color: #16202a; }}
a {{ color: #0f5f9f; text-decoration: none; }}
li {{ margin: 8px 0; }}
</style>
<h1>RadILA Captures</h1>
<ul>{''.join(links)}</ul>
"""


def write_view(input_path, html_path, lanes, title, sample_words):
    samples = load_samples(input_path, sample_words)
    Path(html_path).parent.mkdir(parents=True, exist_ok=True)
    Path(html_path).write_text(render_html(samples, lanes, title, Path(input_path).name), encoding="utf-8")


def write_all_views(capture_dir, lanes, title, sample_words):
    capture_dir = Path(capture_dir)
    for input_path in sorted(capture_dir.rglob("*.bin")):
        write_view(input_path, input_path.with_suffix(".html"), lanes, title, sample_words)


def main():
    parser = argparse.ArgumentParser(description="Receive, render, browse, or serve RadILA captures.")
    parser.add_argument("--listen", action="store_true", help="receive one TCP capture before rendering")
    parser.add_argument("--serve", action="store_true", help="serve the capture directory over HTTP")
    parser.add_argument("--render-all", action="store_true", help="render all .bin captures in the capture directory tree")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=9000)
    parser.add_argument("--http-port", type=int, default=8788)
    parser.add_argument("--capture-dir", default="/tmp/radila-captures")
    parser.add_argument("--input", default="radila-capture.bin")
    parser.add_argument("--html", default="")
    parser.add_argument("--sample-words", type=int, default=1)
    parser.add_argument("--lane", action="append", default=[], help="name:width[:signed] or name:hi:lo[:signed]")
    parser.add_argument("--title", default="RadILA Capture")
    args = parser.parse_args()

    capture_dir = Path(args.capture_dir)
    capture_dir.mkdir(parents=True, exist_ok=True)
    input_path = Path(args.input)
    if not input_path.is_absolute():
        input_path = capture_dir / input_path
    html_path = Path(args.html) if args.html else input_path.with_suffix(".html")
    if not html_path.is_absolute():
        html_path = capture_dir / html_path

    if args.listen:
        receive(input_path, args.host, args.port)
    if input_path.exists():
        write_view(input_path, html_path, parse_lanes(args.lane), args.title, args.sample_words)
    if args.render_all or args.serve:
        write_all_views(capture_dir, parse_lanes(args.lane), args.title, args.sample_words)
    (capture_dir / "index.html").write_text(render_index(capture_dir), encoding="utf-8")
    print(html_path)

    if args.serve:
        handler = lambda *a, **kw: SimpleHTTPRequestHandler(*a, directory=str(capture_dir), **kw)
        ThreadingHTTPServer((args.host, args.http_port), handler).serve_forever()


if __name__ == "__main__":
    main()
