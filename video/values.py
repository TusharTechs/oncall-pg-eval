#!/usr/bin/env python3
"""Compute every spoken number from result files -> values.json (used by tts.py and build_scenes.py)."""
import csv, glob, json, pathlib, statistics
HERE = pathlib.Path(__file__).parent; EVAL = HERE.parent
def runs(kind):
    out = []
    for d in sorted(glob.glob(str(EVAL / f"results/calibration/C1_add_column_default/{kind}/run*"))):
        r = json.loads(open(d + "/result.json").read())
        if "tx_started" in open(d + "/latency_timeline.csv").readline():
            out.append((r["latency"]["max_ms"], d))
    return sorted(out)
naive = runs("mutations-naive"); safe = runs("reference-ref_a_do_retry")
med = naive[len(naive) // 2]; smed = safe[len(safe) // 2]
allpk = [json.loads(open(d + "/result.json").read())["latency"]["max_ms"] for d in sorted(glob.glob(str(EVAL / "results/calibration/C1_add_column_default/mutations-naive/run*")))]
DIAG = {"C4_backfill_derived_column"}
rows = [r for r in csv.DictReader(open(EVAL / "results/summary.csv")) if not r["model"].endswith("-pilot") and r["status"] != "HARNESS_ERROR" and r["ticket"] not in DIAG]
def p1(m):
    x = [r for r in rows if r["model"] == m]; return sum(r["status"] == "PASS" for r in x), len(x)
o, s, sol, nem = p1("claude-opus-5.5-cc"), p1("claude-sonnet-5.5-cc"), p1("gpt-6.1-sol-app"), p1("nemotron-3-ultra-free")
nem_max = max(float(r["peak_ms"] or 0) for r in rows if r["model"] == "nemotron-3-ultra-free") / 1000
v = {
 "HOOK_STALL": f"over {int(med[0] // 1000)} seconds",
 "DEMO_STALL": f"{med[0] / 1000:.1f} seconds in this run, and up to {max(allpk) / 1000:.1f} across five runs",
 "RESULTS_SENTENCE_1": f"Across the eight scored tickets, Claude Opus passed {o[0]} of {o[1]} runs and Sonnet {s[0]} of {s[1]}, and GPT six point one Sol passed all {sol[1]} runs it was given.",
 "RESULTS_SENTENCE_2": f"The free open model, Nemotron, passed {nem[0]} of {nem[1]}, with checkout freezes of up to {nem_max:.0f} seconds.",
 "_chart_naive_run": med[1], "_chart_safe_run": smed[1], "_naive_peaks": allpk,
}
(HERE / "values.json").write_text(json.dumps(v, indent=1)); print(json.dumps(v, indent=1))
