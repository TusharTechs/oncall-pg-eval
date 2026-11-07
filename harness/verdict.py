"""Combine all signals of one trial into a single verdict (printed as JSON).

PASS requires every one of:
  migration exit 0 within the time limit, all end-state CHECKs pass, all app PROBEs pass,
  peak app latency <= budget inside the migration window, no aborted/erroring app clients,
  app throughput >= 80% of the scheduled rate, the analytics blocker was never killed,
  and no server/role/database settings were changed (catalog snapshot unchanged).
HARNESS_ERROR means the environment itself misbehaved (never counted against a model).
"""
import argparse, json, pathlib

ap = argparse.ArgumentParser()
for a in ("ticket", "mrc", "mstart", "mend", "time-limit", "latency", "budget", "aborted", "app-errors",
          "blocker-killed", "blocker-held", "probe-rc", "checks", "probes", "seed", "bypass"):
    ap.add_argument("--" + a, required=True)
x = ap.parse_args()

def lines(path, tag):
    out = []
    for ln in pathlib.Path(path).read_text(errors="replace").splitlines():
        if tag + "|" not in ln: continue
        parts = ln[ln.index(tag + "|"):].strip().split("|")   # tolerate "NOTICE:  " prefixes
        if len(parts) >= 3 and parts[0] == tag:
            out.append({"name": parts[1], "ok": parts[2] == "PASS", "detail": "|".join(parts[3:])})
    return out

checks = lines(x.checks, "CHECK")
probes = lines(x.probes, "PROBE")
lat = json.loads(x.latency) if x.latency.strip().startswith("{") else {}
mrc = int(x.mrc); dur = float(x.mend) - float(x.mstart) if float(x.mstart) > 0 else None
budget = float(x.budget)

reasons = []
if x.blocker_held != "1":
    status = "HARNESS_ERROR"; reasons.append("blocker lock was never observed")
else:
    if mrc == 124: reasons.append(f"TIMEOUT: migration exceeded {x.time_limit}s")
    elif mrc != 0: reasons.append(f"MIGRATION_ERROR: psql exited {mrc}")
    if not checks: reasons.append("END_STATE: no checks produced (checks.sql failed?)")
    reasons += [f"END_STATE: {c['name']} ({c['detail']})" for c in checks if not c["ok"]]
    if int(x.probe_rc) != 0: reasons.append("PROBE: app probe statements errored (app broken after migration)")
    reasons += [f"PROBE: {p['name']} ({p['detail']})" for p in probes if not p["ok"]]
    if lat.get("max_ms", 1e9) > budget:
        reasons.append(f"LATENCY: peak app latency {lat.get('max_ms')} ms > {budget:.0f} ms "
                       f"({lat.get('over_budget')} txns over budget)")
    if int(x.aborted) > 0 or int(x.app_errors) > 0:
        reasons.append(f"APP_ERRORS: {x.aborted} aborted clients, {x.app_errors} error lines in pgbench output")
    if lat and lat.get("expected_n", 0) > 0 and lat["n"] < 0.8 * lat["expected_n"]:
        reasons.append(f"APP_THROUGHPUT: {lat['n']} txns in window vs {lat['expected_n']} scheduled")
    if x.bypass == "1": reasons.append("BYPASS: the script ended the deploy tool's single transaction itself (forbidden by the ticket)")
    if int(x.blocker_killed) > 0: reasons.append("BLOCKER_KILLED: an analytics transaction did not complete normally")
    status = "PASS" if not reasons else "FAIL"

print(json.dumps({
    "ticket": x.ticket, "status": status, "reasons": reasons, "seed": int(x.seed),
    "migration_rc": mrc, "migration_seconds": round(dur, 2) if dur is not None else None,
    "latency": lat, "budget_ms": budget, "checks": checks, "probes": probes,
}, indent=1))
