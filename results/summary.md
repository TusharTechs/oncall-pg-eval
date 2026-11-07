# Results

| model | channel | C1 | C2 | C3 | C4 | H1 | H2 | H3 | H4 | H5 | pass@1 | pass^k (all trials) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku-5.5 | API (OpenRouter) | 1/1 | 1/1 | 1/1 | (0/1) | 0/1 | 1/1 | 0/1 | – | – | 67% | 4/6 tickets |
| claude-opus-5.5-cc | Claude Code subagent | 3/3 | 3/3 | 3/3 | (3/3) | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 96% | 7/8 tickets |
| claude-sonnet-5.5-cc | Claude Code subagent | 3/3 | 3/3 | 3/3 | (3/3) | 2/3 | 3/3 | 3/3 | 3/3 | 3/3 | 96% | 7/8 tickets |
| gpt-6-astra-app | chat-app paste | – | – | – | – | 1/1 | 1/1 | 1/1 | 1/1 | – | 100% | 4/4 tickets |
| gpt-6.1-sol-app | chat-app paste | 3/3 | 3/3 | – | – | 1/1 | 1/1 | 1/1 | 1/1 | 3/3 | 100% | 7/7 tickets |
| nemotron-3-ultra-free | API (OpenRouter) | 2/3 | 0/3 | 3/3 | (0/3) | 0/3 | 2/3 | 1/3 | 3/3 | 0/3 | 46% | 2/8 tickets |

Tickets in parentheses are diagnostic only and excluded from pass@1 / pass^k: C4_backfill_derived_column (references did not pass 5/5 in calibration).

## Failures

| model | ticket | trial | status | peak ms | first reason |
|---|---|---|---|---|---|
| claude-haiku-5.5 | C4_backfill_derived_column | trial1 | NO_VALID_OUTPUT | None | INCOMPLETE_OUTPUT: finish_reason=length |
| claude-haiku-5.5 | H1_volatile_default_uuid | trial1 | FAIL | 158.9 | APP_ERRORS: 9 aborted clients, 9 error lines in pgbench output |
| claude-haiku-5.5 | H3_failed_previous_attempt | trial1 | NO_VALID_OUTPUT | None | INCOMPLETE_OUTPUT: finish_reason=length |
| claude-opus-5.5-cc | H1_volatile_default_uuid | trial3 | FAIL | 110.6 | APP_ERRORS: 9 aborted clients, 9 error lines in pgbench output |
| claude-sonnet-5.5-cc | H1_volatile_default_uuid | trial2 | FAIL | 58.3 | APP_ERRORS: 9 aborted clients, 9 error lines in pgbench output |
| nemotron-3-ultra-free | C1_add_column_default | trial2 | FAIL | 5546.5 | LATENCY: peak app latency 5546.5 ms > 500 ms (1045 txns over budget) |
| nemotron-3-ultra-free | C2_fk_and_not_null | trial1 | FAIL | 9787.5 | LATENCY: peak app latency 9787.5 ms > 500 ms (1853 txns over budget) |
| nemotron-3-ultra-free | C2_fk_and_not_null | trial2 | FAIL | 5549.3 | LATENCY: peak app latency 5549.3 ms > 500 ms (1072 txns over budget) |
| nemotron-3-ultra-free | C2_fk_and_not_null | trial3 | FAIL | 11441.5 | LATENCY: peak app latency 11441.5 ms > 500 ms (2232 txns over budget) |
| nemotron-3-ultra-free | C4_backfill_derived_column | trial1 | FAIL | 9502.3 | MIGRATION_ERROR: psql exited 3 |
| nemotron-3-ultra-free | C4_backfill_derived_column | trial2 | FAIL | 8316.8 | LATENCY: peak app latency 8316.8 ms > 500 ms (2563 txns over budget) |
| nemotron-3-ultra-free | C4_backfill_derived_column | trial3 | FAIL | 10447.1 | LATENCY: peak app latency 10447.1 ms > 500 ms (2037 txns over budget) |
| nemotron-3-ultra-free | H1_volatile_default_uuid | trial1 | FAIL | 6892.7 | LATENCY: peak app latency 6892.7 ms > 500 ms (1994 txns over budget) |
| nemotron-3-ultra-free | H1_volatile_default_uuid | trial2 | FAIL | 5535.7 | LATENCY: peak app latency 5535.7 ms > 500 ms (1095 txns over budget) |
| nemotron-3-ultra-free | H1_volatile_default_uuid | trial3 | FAIL | 10433.0 | LATENCY: peak app latency 10433.0 ms > 500 ms (2069 txns over budget) |
| nemotron-3-ultra-free | H2_int_overflow_emergency | trial2 | FAIL | 8.6 | MIGRATION_ERROR: psql exited 3 |
| nemotron-3-ultra-free | H3_failed_previous_attempt | trial2 | FAIL | 207.2 | MIGRATION_ERROR: psql exited 3 |
| nemotron-3-ultra-free | H3_failed_previous_attempt | trial3 | FAIL | 6.9 | MIGRATION_ERROR: psql exited 3 |
| nemotron-3-ultra-free | H5_null_backfill_then_enforce | trial1 | FAIL | 5884.6 | LATENCY: peak app latency 5884.6 ms > 500 ms (1127 txns over budget) |
| nemotron-3-ultra-free | H5_null_backfill_then_enforce | trial2 | NO_VALID_OUTPUT | None | EMPTY_REPLY |
| nemotron-3-ultra-free | H5_null_backfill_then_enforce | trial3 | FAIL | 8983.6 | LATENCY: peak app latency 8983.6 ms > 500 ms (1714 txns over budget) |
