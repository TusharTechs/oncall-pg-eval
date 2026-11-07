# Text for the HackerRank submission form

## Video walkthrough link
https://youtu.be/NzbBMvh8AKo

## Short description
OnCall-PG is an eval for production change safety on a checkout platform: zero-downtime PostgreSQL migrations on a hot 5-million-row orders table. Frontier models can recite PostgreSQL's locking rules (six models scored 87–89/89 on our expert quiz), so OnCall-PG tests whether they apply them. Each of 9 on-call tickets is answered with a migration script that a real PostgreSQL 17 grades under live load (200 app tx/s plus long analytics reads). It passes only if the end state is right, fresh app writes still behave, no app transaction waits over 500 ms and no app connection errors. There is no LLM judge; references pass 80/80 runs and deliberately wrong scripts fail 115/115. Across the 8 scored tickets, Claude Opus 5.5 and Sonnet 5.5 passed 23/24 runs and GPT-6.1 Sol 13/13, while the open Nemotron-3 Ultra passed 11/24 with checkout freezes up to 11 s. The key frontier failure: Opus, Sonnet and Haiku each added a CHECK ... NOT VALID constraint before backfilling. PostgreSQL still enforces it on updated rows, so the app's routine UPDATE crashed and all 8 app connections died, with perfect schema and latency. Only executing the plan against a live system reveals it.
