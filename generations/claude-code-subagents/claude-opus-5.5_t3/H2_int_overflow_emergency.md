```sql
-- H2: events.id (int identity) is ~5,000 values from 2^31-1.
-- Emergency fix, zero locking: all 2,000,000 existing ids sit just below the
-- integer maximum, so the range 1 .. ~2,145,483,646 is completely unused.
-- Point the identity sequence back at 1: the next ~2.14 billion inserts get fresh,
-- non-colliding ids (>= 1,000,000,000 required), existing ids are untouched, and
-- the app needs no change.
--
-- setval() is non-transactional, takes effect immediately, and takes no lock on
-- the events table, so it neither blocks the app nor waits on the analytics job.
-- The full int -> bigint conversion of events.id is deferred to a planned
-- maintenance window (allowed by the ticket).

SET statement_timeout = 0;

-- Sanity check: make sure the low id range really is free before reusing it.
DO $$
DECLARE
  min_id bigint;
BEGIN
  SELECT min(id) INTO min_id FROM events;
  IF min_id IS NOT NULL AND min_id <= 1000000000 THEN
    RAISE EXCEPTION 'unexpected: events has ids as low as %, low range not free', min_id;
  END IF;
END
$$;

-- Restart the identity sequence at 1 (next nextval() returns 1).
SELECT setval(pg_get_serial_sequence('events', 'id'), 1, false);

-- Verify: the sequence is now well below every existing id.
DO $$
DECLARE
  min_id   bigint;
  seq_last bigint;
  seq_called boolean;
BEGIN
  SELECT last_value, is_called INTO seq_last, seq_called FROM events_id_seq;
  SELECT min(id) INTO min_id FROM events WHERE id > 1000000000;
  IF min_id IS NOT NULL AND min_id - seq_last < 1000000000 THEN
    RAISE EXCEPTION 'insufficient headroom: seq at %, lowest high id %', seq_last, min_id;
  END IF;
END
$$;
```
