#!/usr/bin/env python3
"""Inject real data into scenes.template.html -> build/scenes.html. Every number on screen comes from result files.

  python3 build_scenes.py [--calib ../oncall-pg-eval/results/calibration_<stamp>.txt] [--end-hold 5]
"""
import argparse, csv, glob, json, pathlib, re, sys, collections

HERE = pathlib.Path(__file__).parent; EVAL = HERE.parent
ap = argparse.ArgumentParser(); ap.add_argument("--calib"); ap.add_argument("--end-hold", type=float, default=5.0)
ap.add_argument("--allow-placeholder", action="store_true")
a = ap.parse_args()
warn = []

timings = json.loads((HERE / "build" / "timings.json").read_text())

# ---- Pilot 1 (from RESEARCH_REPORT / pilot answers; per-model trials) ----
pilot1 = [["Claude Opus 5.5 (2 trials)", 89], ["GPT-6.1 Sol, high", 89], ["GPT-6 Astra, high", 89],
          ["Claude Sonnet 5.5 (2 trials)", 88.5], ["Claude Haiku 5.5 (2 trials)", 87], ["Gemini 3.8 Flash, high", 87]]

# ---- C1 latency timelines: newest runs that use the scheduled-start timeline format ----
def pick_timeline(kind):
    best = None
    for f in sorted(glob.glob(str(EVAL / f"results/calibration/C1_add_column_default/{kind}/run*/latency_timeline.csv"))):
        head = open(f).readline()
        if "tx_started" in head:
            r = json.loads(open(pathlib.Path(f).parent / "result.json").read())
            best = (f, r)
    return best
def load_series(f, label, color, lo=-3, hi=None):
    pts = []
    for row in csv.DictReader(open(f)):
        s = int(row["second"])
        if s >= lo and (hi is None or s <= hi): pts.append([s, round(float(row["max_latency_ms"]), 1)])
    return {"label": label, "color": color, "points": sorted(pts)}
V = json.loads((HERE / "values.json").read_text())
def run_of(d): return (d + "/latency_timeline.csv", json.loads(open(d + "/result.json").read()))
nv, sf = run_of(V["_chart_naive_run"]), run_of(V["_chart_safe_run"])
if nv and sf:
    hi = max(int(r["second"]) for r in csv.DictReader(open(nv[0]))) - 1
    naive = load_series(nv[0], "Naive ALTER", "#d95926", hi=hi); safe = load_series(sf[0], "Safe migration", "#3987e5", hi=hi)
    naive_peak, naive_over = nv[1]["latency"]["max_ms"], nv[1]["latency"]["over_budget"]; safe_peak = sf[1]["latency"]["max_ms"]
    src = f"naive={nv[0]} safe={sf[0]}"
else:
    if not a.allow_placeholder: sys.exit("no scheduled-start C1 timelines yet (run after calibration) or pass --allow-placeholder")
    warn.append("PLACEHOLDER C1 chart data")
    naive = {"label": "Naive ALTER", "color": "#d95926", "points": [[-3,6],[-2,7],[-1,8],[0,9500],[1,8600],[2,7500],[4,5400],[6,3300],[8,1200],[9,40],[11,8],[13,7]]}
    safe = {"label": "Safe migration", "color": "#3987e5", "points": [[-3,6],[-2,7],[-1,8],[0,40],[1,55],[2,60],[4,30],[6,20],[8,12],[9,9],[11,8],[13,7]]}
    naive_peak, naive_over, safe_peak, src = 9508.8, 1833, 58.1, "placeholder"

# ---- calibration matrix ----
calib_file = a.calib or (sorted(glob.glob(str(EVAL / "results/calibration_2*.txt"))) or [None])[-1]
agg = collections.OrderedDict()
if calib_file and pathlib.Path(calib_file).exists():
    for ln in open(calib_file):
        m = re.match(r"^(\S+)\s+(reference|mutations)\s+(\S+)\s+(\d+)/(\d+) pass\s", ln)
        if not m: continue
        tid, kind, name, p, n = m.group(1), m.group(2), m.group(3), int(m.group(4)), int(m.group(5))
        if kind == "mutations" and not (EVAL / "tickets" / tid / "mutations" / f"{name}.sql").exists(): continue   # moved to borderline/
        if kind == "reference" and not (EVAL / "tickets" / tid / "reference" / f"{name}.sql").exists(): continue
        d = agg.setdefault(tid, {"ref": [0, 0, 0], "mut": [0, 0, 0]})   # scripts, runs_ok, runs_total
        k = "ref" if kind == "reference" else "mut"
        d[k][0] += 1; d[k][1] += (p if k == "ref" else n - p); d[k][2] += n
else:
    warn.append("no calibration file")
SHORT = {"C1": "add column + default", "C2": "NOT NULL + FK", "C3": "unique constraint", "C4": "backfill derived col",
         "H1": "volatile default", "H2": "int4 overflow", "H3": "failed prior attempt", "H4": "single-txn deploy", "H5": "repair, then enforce"}
calib = [{"t": t.split("_")[0] + " · " + SHORT.get(t.split("_")[0], ""),
          "ref": f"{v['ref'][1]}/{v['ref'][2]} pass", "refOk": v["ref"][1] == v["ref"][2],
          "mut": f"{v['mut'][1]}/{v['mut'][2]} fail", "mutOk": v["mut"][1] == v["mut"][2]}
         for t, v in agg.items()]

# ---- results table (from evalpg report output) ----
rows = [r for r in csv.DictReader(open(EVAL / "results/summary.csv")) if not r["model"].endswith("-pilot")]
tickets = sorted({r["ticket"].split("_")[0] for r in rows})
NAMES = {"claude-opus-5.5-cc": ("Claude Opus 5.5", "Claude Code subagent"), "claude-sonnet-5.5-cc": ("Claude Sonnet 5.5", "Claude Code subagent"),
         "gpt-6.1-sol-app": ("GPT-6.1 Sol (high)", "ChatGPT app, tools off"), "gpt-6-astra-app": ("GPT-6 Astra (high)", "ChatGPT app, tools off"),
         "claude-haiku-5.5": ("Claude Haiku 5.5", "OpenRouter API"), "nemotron-3-ultra-free": ("Nemotron-3 Ultra (free)", "OpenRouter API")}
order = list(NAMES)
res_rows = []
for m in order:
    rs = [r for r in rows if r["model"] == m and r["status"] != "HARNESS_ERROR"]
    if not rs: continue
    cells = []
    for t in tickets:
        x = [r for r in rs if r["ticket"].startswith(t + "_")]
        c = f"{sum(r['status'] == 'PASS' for r in x)}/{len(x)}" if x else "–"
        cells.append(f"({c})" if (t == "C4" and x) else c)
    scored = [r for r in rs if not r["ticket"].startswith("C4_")]
    p1 = sum(r["status"] == "PASS" for r in scored) / len(scored)
    res_rows.append({"model": NAMES[m][0], "channel": NAMES[m][1], "cells": cells, "p1": f"{p1:.0%}"})
h5 = [r for r in rows if r["ticket"].startswith("H5_") and r["model"] in ("claude-opus-5.5-cc", "claude-sonnet-5.5-cc", "gpt-6.1-sol-app")]
h5_txt = f"{sum(r['status'] == 'PASS' for r in h5)} / {len(h5)}"

total = timings["total"] + a.end_hold
data = {"timings": timings, "total": total, "pilot1": pilot1, "c1": {"naive": naive, "safe": safe},
        "calib": calib, "results": {"tickets": tickets, "rows": res_rows}}
html = (HERE / "scenes.template.html").read_text()
html = html.replace("__DATA__", json.dumps(data)).replace("__NAIVE_PEAK__", f"{naive_peak:,.0f}").replace("__NAIVE_OVER__", f"{naive_over:,}")
pk = V["_naive_peaks"]
html = html.replace("__RANGE__", f"5 runs: {min(pk)/1000:.1f} – {max(pk)/1000:.1f} s stall · median {sorted(pk)[len(pk)//2]/1000:.1f} s")
tk = [x for x in timings["scenes"] if x["id"] == "takeaway"][0]
html = html.replace("__END_CARD_AT__", f"{tk['sentences'][-1]['end'] - tk['start'] + 0.3:.2f}")
import re as _re
log_n = len(_re.findall(r"^### C\d+\.", (HERE.parent / "docs" / "CHALLENGES_LOG.md").read_text(), _re.M))
html = html.replace("__LOG_N__", str(log_n))
html = html.replace("__SAFE_PEAK__", f"{safe_peak:,.0f}").replace("__H5_FRONTIER__", h5_txt)
html = html.replace("__RESULTS_FOOTNOTE__", "Same prompts for every model. Claude via audited Claude Code subagents (read prompt / write answer only); "
                    "GPT via the ChatGPT app, tools off; Haiku &amp; Nemotron via the OpenRouter API. "
                    "(C4) = diagnostic only, excluded from pass@1. Pilot duplicates and the contaminated agentic-IDE run are excluded. – = not run.")
(HERE / "build" / "scenes.html").write_text(html)
print(f"built scenes.html · total {total:.1f}s · chart {src} · calib {calib_file} · rows {len(res_rows)}")
for w in warn: print("WARNING:", w)
