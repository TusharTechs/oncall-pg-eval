# micro1 Eval Hackathon: research and recommendation

*Prepared 2026-11-06. Submissions close **2026-11-09 05:15 GMT** (Nov 8, 9:15 PM PT).*
*Companion files: [CHALLENGES_LOG.md](CHALLENGES_LOG.md) (everything that went wrong, including AI failures) and [pilots/](pilots/) (the prompts we ran).*

---

## 1. TL;DR

**Build "On-Call, Not Quiz": a PostgreSQL production-migration eval where the real database is the grader.**
The model gets an ops ticket ("make `customer_id` NOT NULL with a validated FK on a hot 5M-row table"). It writes `migration.sql`. The harness runs it against a live PostgreSQL 17 under real app traffic (pgbench) plus a long-running analytics transaction. It PASSES only if:
1. the script exits cleanly,
2. the catalog end state is correct,
3. data is correct (probed with fresh inserts and updates afterwards),
4. no app transaction stalls past the latency budget and no app client errors.

No LLM judge, no hand-written answer key: **Postgres decides.**

Why this design, in one line each:
- **Real gap, measured honestly.** Frontier models ace the *quiz* version of this knowledge (6 models, 87–89 of 89). Most also pass textbook migrations under live load. But GPT-6.1 Sol failed 6/6 runs by retrying a lock too eagerly (0.5–2.8 s app stalls), and a one-line ablation proved that cause. The gap is operational judgment about queueing, not missing knowledge. The harder tickets are designed to probe exactly that.
- **Grader reliability (20 pts) is our strongest card.** The oracle is the real system, the reference scripts pass and the naive ones fail with 18–74× separation, and a mutation suite proves no false passes.
- **Your domain.** Backend/DB/SRE is exactly what the eval needs, so the 10 "human expertise" points and the video come from your own on-call stories.
- **What micro1 sells.** micro1's "Realm" product is expert-authored sandboxed tasks with verifiable rewards, and this is one. Teams that buy environments want precisely this format.

---

## 2. What the judges actually score

The rubric is in the participant guide PDF (section 5), not on the event page:

| Criterion | Pts | What wins it, for us |
|---|---|---|
| Real-world relevance | 15 | Migration-caused outages are one of the most common self-inflicted production incidents. The README cites public postmortems and your own experience. |
| Task design | 20 | Each ticket states every constraint the grader checks (the latency budget, "don't kill sessions", the time limit, the app workload). There is a reference solution per ticket. |
| Grader reliability | 20 | The real DB is the oracle. Reference ×5 runs must pass 5/5, naive and mutation scripts must fail 5/5, and a calibration step runs on the judge's machine. |
| Evidence of limitations | 15 | 5–6 frontier models × 5 trials, pass@1 and pass^5. Each failure is attributed to the exact statement that caused the stall (from a `pg_stat_activity` sampler). |
| Reproducibility | 15 | `make calibrate && make eval MODEL=...` via Docker Compose, with pinned image digest, seed, runtime and $ cost. |
| Human expertise | 10 | Your tickets, your war stories, and a README section on how AI tools were used and checked (the challenges log is evidence). |
| Insight | 5 | "Frontier models know every PostgreSQL lock fact and still take prod down when the environment has one more constraint than the textbook." Final wording depends on the full results. |

Explicit red flags in the guide: 0% everywhere, small models beating big ones, ~100% for the best model (no headroom), graders that check unstated things, LLM judges with vague rubrics, AI-generated filler.

---

## 3. Landscape: what already exists

**micro1** sells expert human data, RL environments ("Realm": expert-authored sandboxed agent tasks with rubric rewards), enterprise agent evals ("Cortex") and "flow". Its last hackathon (Aug 2026, ~5,900 registrants, solo coding-agent sprint) rewarded "correct, reproducible, testable and clearly explained" work. Top performers were offered paid work.

**Public entries we found for this event** are mostly:
- language trivia and output prediction (C# console output, Python scoping), tested only on older or smaller models,
- small synthetic business-logic tasks,
- one "finance MCP" entry whose model results are *simulated* and whose README hides a prompt-injection aimed at AI agents.

Nobody we found grades against a live production system under load.

**Gaps in the public entries we found, and how this design addresses them:**
- They test old or small models. We use current frontier models with multiple trials.
- They simulate runs. We publish real raw outputs and per-run latency logs.
- They grade against hand-written answers. A real system grades ours.
- They read like quizzes. Ours are realistic ops tickets.

---

## 4. What we tested (evidence behind this recommendation)

### Pilot 1: expert "predict the system" quiz. **Result: saturated.**
There were 89 items, with ground truth produced by executing the real systems in Docker:
- Linux ACLs and sticky / `protected_regular` (11),
- PostgreSQL 17 lock mode / rewrite / scan for 20 DDL statements (58),
- Kubernetes NetworkPolicy reachability with AND-vs-OR selector traps (20).

No tools.

| Model (settings) | Items correct / 89 |
|---|---|
| Claude Opus 5.5 (2 trials) | 89, 89 |
| Claude Sonnet 5.5 (2 trials) | 89, 88 |
| GPT-6.1 Sol (high) | 89 |
| GPT-6 Astra (high) | 89 |
| Claude Haiku 5.5 (2 trials) | 87, 87 |
| Gemini 3.8 Flash (high) | 87 |

The only recurring miss: `timestamp → timestamptz` skips the rewrite when TimeZone=UTC (Haiku and Gemini Flash). **Implication:** "does the model know X" evals, which is most of the public entries we found, no longer separate 2026 frontier models. That directly motivates the "apply it under load" design.

### Pilot 2: live-database migration tickets. **Result: see table (updated when the batch completes).**
- **Setup:** PG17, 5M-row `orders`, pgbench app at 200 tx/s, one 10 s analytics transaction, 500 ms app-latency budget.
- **Tickets:** M1 add NOT NULL DEFAULT column; M2 NOT NULL + validated FK; M3 UNIQUE constraint; M4 derived column with backfill, trigger and NOT NULL.

**Grader validation:**

| Ticket | Reference peak latency | Naive peak latency |
|---|---|---|
| M1 | 494 ms ✅ | 9,042 ms ❌ |
| M2 | 268 ms ✅ | 9,371 ms ❌ |
| M3 | 169 ms ✅ | 12,524 ms ❌ |
| M4 | 315 ms ✅ | 12,283 ms ❌ |

**Model results:** *(see section 4b below; filled in from `results/models_v2.txt`)*

What we already see from reading the scripts: every frontier model uses the textbook safe patterns. That means lock_timeout + retry, `NOT VALID` → `VALIDATE`, the CHECK-before-SET-NOT-NULL trick, and `CREATE INDEX CONCURRENTLY` with no lock timeout. GPT-6.1 Sol refused the first version of the prompt, and it was right: our wording ("another may start at any time") made the contract unsatisfiable. That is logged as a spec bug we fixed (C13). The textbook tickets are therefore **controls**, not the headline. The eval's discriminating power has to come from tickets where one more realistic constraint breaks the textbook recipe (section 5).

### Judge panel (Opus) verdict
- **Concept scores:** A (this) ≈ 84/100 if models show a spread, ≈ 72 if saturated. Agentic incident version ≈ 74 (can't be validated in 2.5 days). Finance/tax ≈ 62 (not your domain). "Unsatisfiable spec" ≈ 66 alone, but good as 2 twin tickets inside A.
- **Red team:** found real grader holes (crashed-client false passes, a gameable M4 end state, tampering via `\!`, a timing leak, autovacuum interference). All are fixable and listed in [CHALLENGES_LOG.md](CHALLENGES_LOG.md) (C18). Closing them *is* the 20-point grader-reliability story.

---

## 5. The submission: "On-Call, Not Quiz" (8–10 tickets)

**Controls (textbook, expected to pass; they show the harness is fair):**
- M1 add column with constant default
- M3 unique constraint via `CREATE INDEX CONCURRENTLY` + `USING INDEX`

**Discriminating tickets.** One more real-world constraint breaks the textbook recipe; every constraint is stated in the ticket:

| # | Ticket | The trap an expert catches | Graded by |
|---|---|---|---|
| T1 | Add `public_id uuid NOT NULL DEFAULT gen_random_uuid()`, distinct per row | A volatile default forces a full rewrite under ACCESS EXCLUSIVE. It is *not* the instant PG11+ path, so it needs add-nullable + trigger + batched backfill. | latency, `count(DISTINCT)` = `count(*)`, no NULLs, fresh-insert probe |
| T2 | FK from orders → customers, where the **analytics job reads `customers`** | `ADD FOREIGN KEY` locks *both* tables, so retries must cover the referenced table. The customers-path workload stalls otherwise. | latency on both workloads, FK validated |
| T3 | Derived column while the app **also updates `amount`** | An INSERT-only trigger, or a read-then-write backfill race, leaves stale values. Needs `BEFORE INSERT OR UPDATE OF amount`, and idempotent batches. | post-run fresh INSERT and UPDATE probes, zero mismatches |
| T4 | Unique constraint where a **previous failed run left an INVALID index** and the role has `statement_timeout = 3s` (stated) | `IF NOT EXISTS` silently reuses the invalid index. The concurrent build is cancelled by the timeout and leaves another invalid one. | constraint exists, zero invalid indexes, exit 0 |
| T5 | Index + unique key on a **range-partitioned** `orders` | `CREATE INDEX CONCURRENTLY` fails on the parent, and a plain index locks every partition. Needs `ON ONLY` + per-partition concurrent builds + `ATTACH PARTITION`. A unique key must include the partition key. | parent index valid, partitions attached, latency |
| T6 | `int4 → bigint` on `orders.id`, with **the sequence ~90 s from overflow** and a child FK | A plain `ALTER TYPE` rewrites for minutes. Models forget the child column and `ALTER SEQUENCE ... AS bigint`. Needs shadow column, trigger, batches and a short swap. | zero app insert failures across the overflow point, types, FKs valid |
| T7 | "Our migration runner wraps each file in one transaction" (stated) | `CONCURRENTLY` and COMMIT-in-loop backfills error out. The script must split work or use a pattern that is legal inside a transaction. | exit status, end state |
| T8a/T8b | **Twin tickets:** the same ticket, once satisfiable and once provably not (e.g., the stated reader *never* releases its lock) | The model must emit a machine-readable `-- STATUS: BLOCKED <reason>` instead of a script that silently violates the contract, and must *not* block on the satisfiable twin. | exact-match status line + harness outcome |

The best existing tickets (M2 and M4) stay in as medium difficulty.

**Models:** Claude Opus 5.5, Sonnet 5.5, Haiku 5.5, GPT-6.1 Sol, GPT-6 Astra, Gemini 3.8 Pro/Flash, plus one open model (DeepSeek/Qwen) through OpenRouter. Settings: 5 trials each, temperature/effort documented, pass@1 and pass^5.

**Cost estimate:** 10 tickets × 8 models × 5 trials ≈ 400 generations, about $15–40 depending on reasoning effort. DB grading is local and free, but takes time: about 1.5–3 min per ticket run. Use an `--only-failures` mode and parallel containers pinned to separate CPU sets.

---

## 6. Build plan (about 2.5 days)

**Day 1 (Nov 6–7): harden the harness (the grader-reliability story).**
- Docker Compose with three services: db, app (pgbench), client (runs migration.sql as a non-superuser owner role, no `\!`).
- Pinned image digest, `FILE_COPY` + `CHECKPOINT` per trial, autovacuum off on the hot table (documented).
- Analytics reader: randomized duration, and wait until its lock is confirmed held.
- Latency measured only over the migration window. Abort detection.
- Post-run probes (fresh INSERT/UPDATE). Catalog snapshot diff.
- `make calibrate`, plus a mutation suite that must fail 5/5.

**Day 2 (Nov 7–8): tickets and runs.**
- Write T1–T8. Two independent reference scripts each; both must pass 5/5.
- An OpenRouter runner that saves raw responses and detects truncation.
- Run all models × 5 trials. Add a lock-wait sampler to attribute each failure to a statement.

**Day 3 (Nov 8, before 9 PM PT): write-up and video.**
- README: domain, gap, results table, failure analysis per ticket with transcript excerpts, hot take, AI-use disclosure, prior work and sources.
- 5-minute video: problem (1 min), one ticket live with the latency graph spiking (1.5 min), results plus two failure walkthroughs (2 min), takeaway (0.5 min).
- Zip check (<50 MB, no keys, `.env.example` only). Submit early, then update.

---

## 7. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Hard tickets also saturate | Pilot each new ticket on Opus + GPT-6.1 Sol *first*, and keep only tickets with an expert-explainable miss. Even partial saturation is a reportable finding if the controls vs hard tickets show a gradient. |
| Latency flakiness on judges' hardware | Calibration gate, a budget far above the reference peak (ref ≤ 40% of budget), and 5 runs. Naive scripts stall 9–12 s, so the margin is huge. |
| Judges can't run Docker or don't want to pay | Ship all raw outputs + logs. `make regrade` re-grades the saved model outputs locally with **no API key**, so only generation needs keys. |
| Looks AI-generated | Your own ticket write-ups and incident anecdotes. The challenges log shows real human review (spec bug fixed, integrity slip caught, harness bugs found). |
| Prior work / originality | Disclose the inspirations: strong_migrations, the Braintree/GitLab migration guides, Terminal-Bench/Harbor task format, τ-bench's end-state grading. The tickets and harness are new. |

---

## 4b. Pilot 2 model results

Final pilot results (all runs complete, 2026-11-06). Each cell is the peak app latency during the migration. ✅ means it passed everything: exit 0, end state, data, latency ≤ 500 ms, no app failures, no aborted clients (checked in every run).

| Model / trial | M1 | M2 | M3 | M4 |
|---|---|---|---|---|
| Opus 5.5 t1 | ✅ 181 ms | ✅ 220 | ✅ 143 | ✅ 327 |
| Opus 5.5 t2 | ✅ 312 | ✅ 280 | ✅ 107 | ✅ 271 |
| Sonnet 5.5 t2 | ✅ 182 | ✅ 101 | ✅ 103 | ✅ 292 |
| Sonnet 5.5 t3 | ✅ 133 | ✅ 163 | ✅ 121 | ✅ 325 |
| Sonnet 5.5 t1 | ✅ 252 | ✅ 154 | ✅ 156 | ⚠️ output truncated (infra, not a model error) |
| Haiku 5.5 t1 | ✅ 263 | ✅ 258 | ✅ 119 | ✅ 321 |
| Haiku 5.5 t2 | ✅ 266 | ✅ 386 | ✅ 73 | ✅ 261 |
| GPT-6 Astra (high) | ✅ 159 | ✅ 181 | ✅ 105 | ✅ 245 |
| Gemini 3.8 Flash (high) | ✅ 87 | ✅ 92 | ✅ 96 | ✅ 164 |
| **GPT-6.1 Sol (high)** | ❌ **1,863 / 2,840 / 567** (3 runs) | ❌ **2,613 / 534 / 706** (3 runs) | ✅ 89 | ✅ 423 |

**The first real frontier failure: GPT-6.1 Sol's retry duty cycle.** Sol used the textbook pattern (lock_timeout + retry) but chose a 175 ms lock wait with only a 10 ms pause between attempts. While an ACCESS EXCLUSIVE request waits in the lock queue, every app write queues behind it. So during the ~9 s the analytics reader held its lock, the app could write only ~5% of the time, and the backlog snowballed into 0.5–2.8 s stalls. It failed 6/6 runs.

**Causal ablation** (one-line change to the sleep only):
- Sol's own M1 with a 200 ms pause → ✅ 236 ms.
- Our reference M1 with a 10 ms pause → ❌ 1,818 ms.

The cause is the ratio of lock-wait time to pause, not the model's choice of statements. GPT-6 Astra used a 50 ms wait with a 10 ms pause and stayed safe at our load. A human DBA keeps the lock-queue duty cycle low, or adds jittered backoff. No model mentioned the ratio.

**Reading:**
- 9 of 10 model configurations pass the textbook tickets. The well-known playbook is saturated, and only parameter judgment separates models.
- The duty-cycle failure is real, explainable, causally tested, and a known production anti-pattern ("retry storms" behind a lock queue).
- The ticket design can lean into it honestly. Raise app load to realistic peak (e.g. 600–1,000 tx/s) and stretch the blocker window, both stated in the ticket. Retry parameters that are fine at 200 tx/s then collapse, which separates models that reason about queueing from those that copy a snippet.
- The submission still leads with tickets T1–T8 (section 5). M1–M4 stay as controls.

**Caveat for the write-up:** two of Sol's six runs exceeded the budget only slightly (534 and 567 ms), while our reference peaked at 494 ms. Before submitting, the budget and load must be calibrated so the reference sits ≤ 40% of the budget across 5 runs. The current margin is too thin to claim "no false fails" (see C12 and C18).

---

## Sources
- micro1 Eval Hackathon event page and FAQ: https://www.hackerrank.com/event/micro1-eval-hackathon , https://www.micro1.ai/hackathon/faq
- Participant guide PDF (rubric, section 5): https://hrcdn.net/s3_pub/istreet-assets/R_8vs8ejamSPapSbUxmcWQ/Eval_Hackathon_Participant_Guide.pdf
- micro1 vendor profile (third-party): https://www.rl-list.com/vendors/micro1
- Previous micro1 hackathon write-up: https://dev.to/marvinoka4/5900-engineers-just-registered-for-a-hackathon-where-using-ai-is-the-point-heres-how-it-will-1bdd
- Public entries reviewed: https://github.com/karterisg/Micro1-Eval-Hackathon , https://github.com/dl88jing/micro1-frontier-evals , https://gamai-io.github.io/evidence-first-agent-runtime/ (and others listed in the research notes)
- Failure-mode literature: Exception Chain Collapse https://arxiv.org/abs/2607.23386 ; MBABench-2.0 https://arxiv.org/abs/2610.31711 ; TaxCalcBench https://arxiv.org/abs/2507.16126
- Eval-design guidance cited by the organisers: anthropic.com/research/demystifying-evals-for-ai-agents
