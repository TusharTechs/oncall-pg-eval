```sql
-- M1: The stated guarantees cannot all be satisfied.
--
-- ADD COLUMN requires ACCESS EXCLUSIVE, including PostgreSQL's fast
-- constant-default path. Analytics transactions hold ACCESS SHARE
-- until transaction end.
--
-- The permitted workload can maintain overlapping readers throughout
-- all 45 seconds, although each reader lasts at most 10 seconds.
-- Waiting for ACCESS EXCLUSIVE queues new application writes behind it,
-- violating the 500 ms limit. Short timeouts or NOWAIT retries avoid
-- that prolonged blocking but cannot guarantee acquiring the lock.
--
-- Therefore no production migration.sql can guarantee this contract.
```

```sql
-- M2: The stated guarantees cannot all be satisfied.
--
-- A NOT VALID foreign key and subsequent validation can reduce blocking.
-- A validated CHECK can let SET NOT NULL avoid scanning the table.
-- However, SET NOT NULL still requires ACCESS EXCLUSIVE in PostgreSQL 17.
--
-- Permitted overlapping analytics readers can prevent that lock from
-- being granted throughout the deadline. Waiting long enough blocks
-- new application writes beyond 500 ms; bounded retries cannot
-- guarantee completing the required attnotnull change.
--
-- Therefore no production migration.sql can guarantee this contract.
```

```sql
-- M3: The stated guarantees cannot all be satisfied.
--
-- CREATE UNIQUE INDEX CONCURRENTLY permits application writes, but
-- attaching it with ADD CONSTRAINT ... UNIQUE USING INDEX requires
-- ACCESS EXCLUSIVE. A unique index alone does not satisfy this ticket.
--
-- Permitted overlapping analytics readers can prevent the attachment
-- lock throughout the deadline. An extended queued request violates
-- application latency; short retries cannot guarantee attachment.
--
-- Additionally, no execution-time bound for building the index is
-- supplied. Therefore no production migration.sql can guarantee this
-- contract.
```
