#!/usr/bin/env python3
"""OnCall-PG eval runner. Standard library only (Python >= 3.11).

  python3 evalpg/run_eval.py prompt   <ticket>                       # print the exact prompt a model sees
  python3 evalpg/run_eval.py generate --models opus-5.5,gpt-6.1-sol --trials 5 [--tickets C1,C2]
  python3 evalpg/run_eval.py import   --model gpt-6.1-sol-app --ticket C1 --trial 1 --file reply.md
  python3 evalpg/run_eval.py grade    [--models ...] [--tickets ...] [--force]   # needs Docker, no API key
  python3 evalpg/run_eval.py report                                  # results/summary.md + summary.csv

Raw model responses are saved verbatim under transcripts/<model>/<ticket>/trialN.json.
"""
import argparse, csv, datetime, hashlib, json, os, pathlib, re, subprocess, sys, time, tomllib, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
TICKETS = ROOT / "tickets"
TRANSCRIPTS = ROOT / "transcripts"
RESULTS = ROOT / "results" / "runs"
DEFAULTS = dict(TIME_LIMIT=45, APP_RATE=200, APP_CLIENTS=8, WORKLOAD="_common/default.pgbench", BLOCKER_TABLE="orders",
                HOLD_MIN_MS=6000, HOLD_MAX_MS=12000, GAP_MIN_MS=1000, GAP_MAX_MS=3000, BUDGET_MS=500)


# ---------------------------------------------------------------- tickets & prompts
def ticket_dirs(selected=None):
    ds = sorted(d for d in TICKETS.iterdir() if d.is_dir() and not d.name.startswith("_"))
    if selected:
        want = [s.strip() for s in selected.split(",")]
        ds = [d for d in ds if any(d.name == w or d.name.split("_")[0] == w for w in want)]
    return ds


def ticket_env(tdir):
    env = dict(DEFAULTS)
    for ln in (tdir / "ticket.env").read_text().splitlines():
        ln = ln.split("#")[0].strip()
        if "=" in ln:
            k, v = ln.split("=", 1); env[k.strip()] = v.strip().strip('"')
    return env


def render_prompt(tdir):
    env = ticket_env(tdir)
    tpl = (TICKETS / "_common" / "environment.md").read_text()
    notes = (tdir / "setup_notes.md").read_text().strip() if (tdir / "setup_notes.md").exists() else ""
    fill = {
        "APP_RATE": env["APP_RATE"], "BLOCKER_TABLE": env["BLOCKER_TABLE"], "TIME_LIMIT": env["TIME_LIMIT"],
        "BUDGET_MS": env["BUDGET_MS"], "WORKLOAD": (TICKETS / env["WORKLOAD"]).read_text().strip(),
        "HOLD_MIN_S": int(env["HOLD_MIN_MS"]) // 1000, "HOLD_MAX_S": int(env["HOLD_MAX_MS"]) // 1000,
        "GAP_MIN_S": int(env["GAP_MIN_MS"]) // 1000, "GAP_MAX_S": int(env["GAP_MAX_MS"]) // 1000,
        "SETUP_NOTES": notes,
    }
    for k, v in fill.items():
        tpl = tpl.replace("{" + k + "}", str(v))
    return tpl.rstrip() + "\n\n" + (tdir / "ticket.md").read_text().strip() + "\n"


def extract_sql(text):
    """Return (sql, problem). The answer must be one fenced sql block; an unclosed fence = truncated."""
    blocks = re.findall(r"```(?:sql|postgresql|psql)?[ \t]*\n(.*?)```", text, re.S | re.I)
    if blocks:
        return blocks[0], (None if len(blocks) == 1 else f"{len(blocks)} code blocks; graded the first")
    if re.search(r"```(?:sql|postgresql|psql)?[ \t]*\n", text, re.I):
        return None, "INCOMPLETE_OUTPUT: unclosed code block (truncated)"
    if text.strip():
        # Lenient: a reply without a fence is graded on substance (the whole reply runs as SQL; prose simply
        # fails in psql). Format non-compliance is recorded, never by itself a fail.
        return text.strip() + "\n", "NO_FENCE: graded the raw reply as SQL"
    return None, "EMPTY_REPLY"


# ---------------------------------------------------------------- models
def load_models():
    return tomllib.loads((ROOT / "evalpg" / "models.toml").read_text())["model"]


def call_openrouter(model, prompt):
    key = os.environ.get("OPENROUTER_API_KEY")
    if not key:
        sys.exit("OPENROUTER_API_KEY is not set (copy .env.example to .env and `set -a; source .env`).")
    body = {"model": model["openrouter_id"], "messages": [{"role": "user", "content": prompt}],
            "max_tokens": model.get("max_tokens", 32000)}
    if "reasoning_effort" in model:
        body["reasoning"] = {"effort": model["reasoning_effort"]}
    if "temperature" in model:
        body["temperature"] = model["temperature"]
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json",
                                          "X-Title": "oncall-pg-eval"})
    t0 = time.time()
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=900) as r:
                resp = json.loads(r.read())
            break
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors="replace")[:500]
            if e.code in (429, 500, 502, 503) and attempt < 3:
                time.sleep(10 * (attempt + 1)); continue
            raise RuntimeError(f"HTTP {e.code}: {msg}")
    return body, resp, round(time.time() - t0, 1)


def cmd_generate(a):
    models = {m["name"]: m for m in load_models()}
    for name in a.models.split(","):
        m = models[name]
        for tdir in ticket_dirs(a.tickets):
            prompt = render_prompt(tdir)
            for k in range(1, a.trials + 1):
                out = TRANSCRIPTS / name / tdir.name / f"trial{k}.json"
                if out.exists() and not a.force:
                    prev = json.loads(out.read_text())
                    if not (prev.get("raw_response") or {}).get("error"):
                        continue          # keep real answers (incl. truncated ones); retry only API errors
                out.parent.mkdir(parents=True, exist_ok=True)
                print(f"[generate] {name} {tdir.name} trial{k} ...", flush=True)
                try:
                    body, resp, secs = call_openrouter(m, prompt)
                    choice = resp["choices"][0]; text = choice["message"].get("content") or ""
                    finish = choice.get("finish_reason") or choice.get("native_finish_reason")
                except Exception as e:  # recorded, never silently dropped
                    body, resp, secs, text, finish = {}, {"error": str(e)}, 0, "", "error"
                sql, problem = extract_sql(text)
                if finish == "length":
                    sql, problem = None, "INCOMPLETE_OUTPUT: finish_reason=length"
                rec = {"model": name, "openrouter_id": m["openrouter_id"], "ticket": tdir.name, "trial": k,
                       "source": "openrouter-api", "date_utc": datetime.datetime.now(datetime.UTC).isoformat(timespec="seconds"),
                       "prompt_sha256": hashlib.sha256(prompt.encode()).hexdigest(), "request": body,
                       "seconds": secs, "finish_reason": finish, "usage": resp.get("usage"),
                       "response_text": text, "extracted_sql": sql, "extract_problem": problem, "raw_response": resp}
                out.write_text(json.dumps(rec, indent=1))


def cmd_import(a):
    tdir = ticket_dirs(a.ticket)[0]
    text = pathlib.Path(a.file).read_text()
    if "```" not in text:   # a bare SQL paste from a chat app
        text = "```sql\n" + text.rstrip() + "\n```\n"
    sql, problem = extract_sql(text)
    out = TRANSCRIPTS / a.model / tdir.name / f"trial{a.trial}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    prompt = render_prompt(tdir)
    out.write_text(json.dumps({"model": a.model, "ticket": tdir.name, "trial": a.trial, "source": a.source,
                               "date_utc": datetime.datetime.now(datetime.UTC).isoformat(timespec="seconds"),
                               "prompt_sha256": hashlib.sha256(prompt.encode()).hexdigest(),
                               "response_text": text, "extracted_sql": sql, "extract_problem": problem}, indent=1))
    print(f"imported -> {out.relative_to(ROOT)} ({problem or 'ok'})")


# ---------------------------------------------------------------- grading
def cmd_grade(a):
    for tf in sorted(TRANSCRIPTS.glob("*/*/trial*.json")):
        rec = json.loads(tf.read_text())
        model, ticket, k = tf.parts[-3], tf.parts[-2], tf.stem
        if (rec.get("raw_response") or {}).get("error"):
            continue   # API/infra error (e.g. HTTP 402): not a model answer; regenerate instead of grading
        if a.models and model not in a.models.split(","): continue
        if a.tickets and not ticket_dirs(a.tickets) or (a.tickets and ticket not in [d.name for d in ticket_dirs(a.tickets)]): continue
        out = RESULTS / model / ticket / k
        if (out / "result.json").exists() and not a.force: continue
        out.mkdir(parents=True, exist_ok=True)
        if rec.get("response_text") is not None:      # always re-extract from the raw reply (source of truth)
            sql, problem = extract_sql(rec["response_text"])
            if rec.get("finish_reason") == "length":
                sql, problem = None, "INCOMPLETE_OUTPUT: finish_reason=length (hit max_tokens)"
            rec["extracted_sql"], rec["extract_problem"] = sql, problem
        if not rec.get("extracted_sql"):
            (out / "result.json").write_text(json.dumps({"ticket": ticket, "status": "NO_VALID_OUTPUT",
                                                         "reasons": [rec.get("extract_problem") or "no SQL"]}, indent=1))
            print(f"[grade] {model} {ticket} {k}: NO_VALID_OUTPUT ({rec.get('extract_problem')})"); continue
        sql_file = out.parent / f"{k}.submitted.sql"; sql_file.write_text(rec["extracted_sql"])
        seed = int(k.replace("trial", ""))
        subprocess.run([str(ROOT / "harness" / "run_trial.sh"), str(TICKETS / ticket), str(sql_file), str(out), str(seed)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        r = json.loads((out / "result.json").read_text())
        print(f"[grade] {model} {ticket} {k}: {r['status']} peak={r.get('latency', {}).get('max_ms')}ms "
              f"{(r['reasons'] or [''])[0][:90]}", flush=True)


def cmd_report(a):
    rows = []
    for rf in sorted(RESULTS.glob("*/*/trial*/result.json")):
        r = json.loads(rf.read_text()); model, ticket, trial = rf.parts[-4], rf.parts[-3], rf.parts[-2]
        rows.append({"model": model, "ticket": ticket, "trial": trial, "status": r["status"],
                     "peak_ms": r.get("latency", {}).get("max_ms"), "reason": (r.get("reasons") or [""])[0]})
    if not rows: sys.exit("no graded results yet")
    with open(ROOT / "results" / "summary.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
    rows = [r for r in rows if not r["model"].endswith("-pilot")]          # pilot duplicates are not reported
    def channel(m):
        for tf in (TRANSCRIPTS / m).glob("*/trial*.json"):
            s = json.loads(tf.read_text()).get("source", "")
            return "API (OpenRouter)" if s == "openrouter-api" else ("Claude Code subagent" if "subagent" in s else "chat-app paste")
        return "?"
    models = sorted({r["model"] for r in rows}); tickets = sorted({r["ticket"] for r in rows})
    diag = {t for t in tickets if ticket_env(TICKETS / t).get("SCORING", "1").split()[0] == "0"}   # diagnostic-only tickets
    lines = ["| model | channel | " + " | ".join(t.split("_")[0] for t in tickets) + " | pass@1 | pass^k (all trials) |",
             "|---|---|" + "---|" * len(tickets) + "---|---|"]
    for m in models:
        cells, tot, ok, allk, nt = [], 0, 0, 0, 0
        for t in tickets:
            rs = [r for r in rows if r["model"] == m and r["ticket"] == t and r["status"] != "HARNESS_ERROR"]
            p = sum(r["status"] == "PASS" for r in rs)
            if t in diag:
                cells.append(f"({p}/{len(rs)})" if rs else "–"); continue
            cells.append(f"{p}/{len(rs)}" if rs else "–"); tot += len(rs); ok += p
            if rs: nt += 1; allk += (p == len(rs))
        lines.append(f"| {m} | {channel(m)} | " + " | ".join(cells) + f" | {ok / tot:.0%} | {allk}/{nt} tickets |")
    if diag: lines += ["", f"Tickets in parentheses are diagnostic only and excluded from pass@1 / pass^k: {', '.join(sorted(diag))} (references did not pass 5/5 in calibration)."]
    fails = [r for r in rows if r["status"] not in ("PASS",)]
    lines += ["", "## Failures", "", "| model | ticket | trial | status | peak ms | first reason |", "|---|---|---|---|---|---|"]
    lines += [f"| {r['model']} | {r['ticket']} | {r['trial']} | {r['status']} | {r['peak_ms']} | {r['reason'][:110]} |" for r in fails]
    (ROOT / "results" / "summary.md").write_text("# Results\n\n" + "\n".join(lines) + "\n")
    print("\n".join(lines))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)
    p = sp.add_parser("prompt"); p.add_argument("ticket")
    g = sp.add_parser("generate"); g.add_argument("--models", required=True); g.add_argument("--tickets"); g.add_argument("--trials", type=int, default=5); g.add_argument("--force", action="store_true")
    i = sp.add_parser("import"); i.add_argument("--model", required=True); i.add_argument("--ticket", required=True); i.add_argument("--trial", type=int, required=True); i.add_argument("--file", required=True); i.add_argument("--source", default="chat-app-paste")
    r = sp.add_parser("grade"); r.add_argument("--models"); r.add_argument("--tickets"); r.add_argument("--force", action="store_true")
    sp.add_parser("report")
    a = ap.parse_args()
    if a.cmd == "prompt": print(render_prompt(ticket_dirs(a.ticket)[0]))
    else: {"generate": cmd_generate, "import": cmd_import, "grade": cmd_grade, "report": cmd_report}[a.cmd](a)


if __name__ == "__main__":
    main()
