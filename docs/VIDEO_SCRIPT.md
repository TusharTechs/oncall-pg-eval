# Video script: OnCall-PG (target 4:30, hard limit 5:00)

You can record the screen with QuickTime (File → New Screen Recording) and narrate live, or record narration separately. An AI voice is allowed. You do not need to show your face. Upload to YouTube as **Unlisted** (anyone with the link can view) or to Loom, then test the link in a private browser window.

Each section below gives the timing, what to show on screen, and what to say. Rephrase the narration in your own words.

---

## 0:00–0:50 · The problem
**Show:** the README title, then the GoCardless post headline (public link in the README).

**Say:**
> I'm a Customer Engineer at a checkout and payments company. When a platform change goes wrong, I'm the one who gets the merchant escalations. Checkouts stall, carts get abandoned.
>
> One of the most common self-inflicted outages is a database migration. The SQL is correct, but it takes a lock at the wrong moment. GoCardless, a payments company, lost its API for about 15 seconds this way. The ALTER TABLE was instant, but it queued behind a long read, and every request queued behind it.
>
> AI assistants now write these migrations. So I asked: do frontier models know how to do this safely? And more importantly, when they do it, does production survive?

## 0:50–1:20 · Knowing is saturated
**Show:** the Pilot 1 table from RESEARCH_REPORT.md (87–89 out of 89).

**Say:**
> First I built the obvious eval: ask models to predict what PostgreSQL, Linux and Kubernetes actually do, with ground truth produced by running the real systems. Six frontier models scored 87 to 89 out of 89. Knowledge is saturated. So the question became whether they can apply it under load.

## 1:20–2:40 · How a task works
**Show:**
1. `make prompt T=H1` scrolling (environment, live traffic, the analytics reader, the 500 ms budget).
2. A terminal running `./harness/run_trial.sh` on the C1 naive mutation.
3. Its `latency_timeline.csv` chart, the spike to ~9.5 s.
4. The same for the reference, flat at ~60 ms.

**Say:**
> Each task is an on-call ticket. The model writes a migration script, and a real PostgreSQL 17 grades it. It's a 5-million-row orders table with an app writing 200 transactions per second and an analytics job holding long read transactions.
>
> A script passes only if:
> - the schema ends up right,
> - fresh app inserts and updates still work,
> - no app transaction waits more than 500 ms,
> - no app client errors.
>
> There's no LLM judge and no answer key I wrote by hand.
>
> Here's what "wrong" looks like. The textbook one-line ALTER is correct SQL, and it freezes every checkout write for nine and a half seconds. The safe version never goes above about 60.

## 2:40–3:10 · Why you can trust the grader
**Show:** the calibration table (N=5), `ls tickets/H2*/reference tickets/H2*/mutations`, and the CHALLENGES_LOG headings.

**Say:**
> - Every ticket has two or three independent reference solutions that must pass 5 out of 5, and deliberately wrong scripts that must fail 5 out of 5.
> - The model's script runs in its own container as a non-superuser. It can't cancel other sessions, write the catalogs or touch the grader.
> - The database caught *my* mistakes too. Two of my own reference answers were wrong. And an agentic IDE read my answer key off the disk, which is why final answers come only from sources with no file access.

## 3:10–4:10 · What the models got wrong
**Show:**
1. The results table.
2. The H1 failing transcript: the `CHECK ... NOT VALID` line, then the `pgbench` error *"violates check constraint"*.
3. The passing Opus H1 script, highlighting its `BEFORE INSERT OR UPDATE` trigger.

**Say:**
> Frontier models do very well on the textbook tickets, and that's a real finding. They know the playbook.
>
> But on H1, adding a public id column, Opus, Sonnet and Haiku each failed in the same way. They added a NOT NULL check marked NOT VALID before backfilling the data. NOT VALID skips existing rows, but Postgres still enforces it on every update. So the app's ordinary "increment quantity" update hit an old row and crashed. All eight app connections died. The schema was perfect and latency was fine; only the app crashing gave it away.
>
> A passing Opus run made the same early check, but added a trigger that fills the value on update. That one line is the expertise.
>
> The free open model, Nemotron, shows the spread the other way: 5 to 10 second checkout freezes on four of the nine tickets.
>
> And in the pilot, GPT-6.1 Sol's retry loop sat in the lock queue 95% of the time and starved the app. I confirmed that by changing only the pause. On the final prompt it chose a safer loop, so I report it as a prompt-sensitive hazard, not a headline.

## 4:10–4:35 · Takeaway
**Show:** the "Insight" section of the README.

**Say:**
> Frontier models have memorised the safe-migration playbook. What they miss is the interaction the playbook doesn't spell out: a constraint that's "not valid" yet still fires, or a retry loop that's polite to the database but not to the app. You only find those by executing the plan against a live system. That's what OnCall-PG does, and everything here runs with one command.

---

### Recording checklist
- [ ] Under 5:00 (aim for 4:30)
- [ ] Audio is clear (test 10 seconds first)
- [ ] No merchant names, ticket IDs or internal details on screen (check the terminal history)
- [ ] No API key visible (never `cat .env` on screen)
- [ ] Link opens in a private window without signing in
- [ ] Link pasted into the README and the submission form
