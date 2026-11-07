#!/usr/bin/env python3
"""Render 'app latency during a migration' as a self-contained HTML chart (inline SVG, hover tooltip, table view).

  python3 evalpg/make_figure.py --title "C1: add a column under live checkout traffic" \
      --series "Safe migration (reference)=results/calibration/C1_add_column_default/reference-ref_a_do_retry/run2/latency_timeline.csv" \
      --series "Naive ALTER TABLE=results/calibration/C1_add_column_default/mutations-naive/run2/latency_timeline.csv" \
      --budget 500 --out results/figures/c1_latency.html

Input CSVs come from harness/load/timeline.sh (bucketed by scheduled start). Standard library only.
Palette: categorical slots 1-2 of the dataviz reference palette (validated light + dark, all checks pass).
"""
import argparse, csv, html, json, pathlib

LIGHT = ["#2a78d6", "#eb6834"]; DARK = ["#3987e5", "#d95926"]

ap = argparse.ArgumentParser()
ap.add_argument("--title", required=True)
ap.add_argument("--series", action="append", required=True, help="Label=path/to/latency_timeline.csv")
ap.add_argument("--budget", type=float, default=500)
ap.add_argument("--out", required=True)
ap.add_argument("--xmin", type=int, default=-3)
ap.add_argument("--xmax", type=int, default=None)
a = ap.parse_args()

series = []
for i, spec in enumerate(a.series):
    label, path = spec.split("=", 1)
    pts = []
    for row in csv.DictReader(open(path)):
        sec = int(row["second"]); mx = float(row["max_latency_ms"])
        if sec >= a.xmin and (a.xmax is None or sec <= a.xmax):
            pts.append((sec, mx, int(row.get("tx_started") or row.get("tx_count") or 0)))
    series.append({"label": label, "points": sorted(pts), "slot": i})

W, H, L, R, T, B = 860, 420, 72, 40, 40, 52
xs = [p[0] for s in series for p in s["points"]]; x0, x1 = min(xs), max(xs)
ymax = max([p[1] for s in series for p in s["points"]] + [a.budget])
ymax = ymax * 1.08
def sx(x): return L + (x - x0) / max(1, (x1 - x0)) * (W - L - R)
def sy(y): return T + (1 - y / ymax) * (H - T - B)

ticks_y = []
step = 10 ** max(0, len(str(int(ymax))) - 1); step = step if ymax / step >= 3 else step / 2
v = 0
while v <= ymax:
    ticks_y.append(v); v += step

parts = []
for v in ticks_y:   # recessive grid
    parts.append(f'<line x1="{L}" x2="{W-R}" y1="{sy(v):.1f}" y2="{sy(v):.1f}" class="grid"/>'
                 f'<text x="{L-8}" y="{sy(v)+4:.1f}" class="tick" text-anchor="end">{int(v):,}</text>')
for x in range(x0, x1 + 1, max(1, (x1 - x0) // 10)):
    parts.append(f'<text x="{sx(x):.1f}" y="{H-B+18}" class="tick" text-anchor="middle">{x}</text>')
parts.append(f'<line x1="{L}" x2="{W-R}" y1="{sy(0):.1f}" y2="{sy(0):.1f}" class="axis"/>')
# budget reference line (muted ink, not a status color), labelled directly
parts.append(f'<line x1="{L}" x2="{W-R}" y1="{sy(a.budget):.1f}" y2="{sy(a.budget):.1f}" class="budget"/>'
             f'<text x="{L+6}" y="{sy(a.budget)-6:.1f}" class="value">latency budget {int(a.budget)} ms</text>')
for s in series:
    d = " ".join(f'{"M" if j == 0 else "L"}{sx(x):.1f},{sy(y):.1f}' for j, (x, y, _) in enumerate(s["points"]))
    parts.append(f'<path d="{d}" class="line s{s["slot"]}"/>')
    lx, ly, _ = max(s["points"], key=lambda p: p[1])          # direct label at the series peak
    ty = sy(ly) - 8 if sy(ly) - 8 > T + 10 else sy(ly) + 16          # name + peak, just above the series peak
    if ly < a.budget * 1.5: ty = sy(a.budget) - 24                      # low series: label sits above the budget line
    parts.append(f'<text x="{sx(lx)+6:.1f}" y="{ty:.1f}" class="label" style="fill:var(--ink)">{html.escape(s["label"])} · peak {ly:,.0f} ms</text>')
parts.append(f'<text x="{(L + W - R) / 2:.1f}" y="{H-12}" class="axislabel" text-anchor="middle">seconds since the migration started (by when each app transaction was scheduled)</text>')
parts.append(f'<text x="18" y="{(T + H - B) / 2:.1f}" class="axislabel" transform="rotate(-90 18 {(T + H - B) / 2:.1f})" text-anchor="middle">worst app transaction latency (ms)</text>')

rows = sorted({p[0] for s in series for p in s["points"]})
table = "<table><thead><tr><th>second</th>" + "".join(f"<th>{html.escape(s['label'])} (max ms)</th>" for s in series) + "</tr></thead><tbody>"
for x in rows:
    table += f"<tr><td>{x}</td>" + "".join(
        f"<td>{next((f'{p[1]:,.1f}' for p in s['points'] if p[0] == x), '–')}</td>" for s in series) + "</tr>"
table += "</tbody></table>"

data = json.dumps([{"label": s["label"], "slot": s["slot"], "points": s["points"]} for s in series])
page = f"""<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>{html.escape(a.title)}</title>
<style>
:root {{ --surface:#fcfcfb; --ink:#0b0b0b; --ink2:#52514e; --grid:#e6e5e1; --s0:{LIGHT[0]}; --s1:{LIGHT[1]}; }}
@media (prefers-color-scheme: dark) {{ :root {{ --surface:#1a1a19; --ink:#f0efec; --ink2:#c3c2b7; --grid:#33332f; --s0:{DARK[0]}; --s1:{DARK[1]}; }} }}
body {{ background:var(--surface); color:var(--ink); font:14px/1.4 -apple-system,system-ui,sans-serif; margin:24px; }}
h1 {{ font-size:18px; margin:0 0 4px; }} p.sub {{ color:var(--ink2); margin:0 0 12px; }}
.grid {{ stroke:var(--grid); stroke-width:1; }} .axis {{ stroke:var(--ink2); stroke-width:1; }}
.budget {{ stroke:var(--ink2); stroke-width:1.5; stroke-dasharray:5 4; }}
.tick {{ fill:var(--ink2); font-size:12px; }} .axislabel {{ fill:var(--ink2); font-size:12px; }}
.label {{ fill:var(--ink); font-size:13px; font-weight:600; }} .value {{ fill:var(--ink2); font-size:12px; }}
.line {{ fill:none; stroke-width:2; stroke-linejoin:round; }} .s0 {{ stroke:var(--s0); }} .s1 {{ stroke:var(--s1); }}
.legend span {{ display:inline-flex; align-items:center; margin-right:18px; color:var(--ink); }}
.legend i {{ width:16px; height:3px; border-radius:2px; margin-right:6px; display:inline-block; }}
#tip {{ position:fixed; pointer-events:none; background:var(--surface); border:1px solid var(--grid); border-radius:6px;
        padding:6px 9px; font-size:12px; box-shadow:0 2px 8px rgba(0,0,0,.12); display:none; }}
#cross {{ stroke:var(--ink2); stroke-width:1; display:none; }}
details {{ margin-top:14px; }} table {{ border-collapse:collapse; font-size:12px; }} td,th {{ padding:2px 10px; text-align:right; border-bottom:1px solid var(--grid); }}
</style></head><body>
<h1>{html.escape(a.title)}</h1>
<p class="sub">Live PostgreSQL 17 · 5M-row orders table · app at 200 tx/s · one analytics read open when the script starts</p>
<div class="legend">{"".join(f'<span><i style="background:var(--s{s["slot"]})"></i>{html.escape(s["label"])}</span>' for s in series)}</div>
<svg id="chart" viewBox="0 0 {W} {H}" style="width:100%;max-width:{W}px;height:auto" role="img" aria-label="{html.escape(a.title)}">
{''.join(parts)}<line id="cross" y1="{T}" y2="{H-B}"/><rect x="{L}" y="{T}" width="{W-L-R}" height="{H-T-B}" fill="transparent" id="hit"/>
</svg><div id="tip"></div>
<details><summary>Table view</summary>{table}</details>
<script>
const S={data}, x0={x0}, x1={x1}, L={L}, R={R}, W={W};
const hit=document.getElementById('hit'), tip=document.getElementById('tip'), cross=document.getElementById('cross'), svg=document.getElementById('chart');
hit.addEventListener('mousemove', e => {{
  const r=svg.getBoundingClientRect(), px=(e.clientX-r.left)*({W}/r.width);
  const sec=Math.round(x0+(px-L)/(W-L-R)*(x1-x0)); const cx=L+(sec-x0)/Math.max(1,x1-x0)*(W-L-R);
  cross.setAttribute('x1',cx); cross.setAttribute('x2',cx); cross.style.display='block';
  tip.innerHTML='<b>second '+sec+'</b><br>'+S.map(s=>{{const p=s.points.find(q=>q[0]===sec);
    return '<span style="color:var(--s'+s.slot+')">&#9644;</span> '+s.label+': '+(p?p[1].toLocaleString()+' ms ('+p[2]+' txns)':'–');}}).join('<br>');
  tip.style.display='block'; tip.style.left=(e.clientX+14)+'px'; tip.style.top=(e.clientY+10)+'px'; }});
hit.addEventListener('mouseleave', ()=>{{ tip.style.display='none'; cross.style.display='none'; }});
</script></body></html>"""
pathlib.Path(a.out).parent.mkdir(parents=True, exist_ok=True)
pathlib.Path(a.out).write_text(page)
print("wrote", a.out)
