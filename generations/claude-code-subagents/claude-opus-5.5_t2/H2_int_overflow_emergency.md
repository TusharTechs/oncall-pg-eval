```sql
-- Ticket H2: events.id (int identity) is ~5,000 values from overflow.
--
-- Emergency fix, no table locks, no rewrite, effective immediately:
-- the existing 2,000,000 ids all sit just below the int maximum, so the whole
-- range 1 .. ~2,145,000,000 is unused. Restart the identity sequence at 1.
-- setval() is non-transactional and takes no lock on events, so it neither
-- blocks the app nor waits for the analytics reader. That leaves >2.1 billion
-- collision-free ids (requirement: 1,000,000,000). No existing id changes.
-- The int -> bigint conversion is deferred to a maintenance window.

SET statement_timeout = 0;
SET lock_timeout = '1s';

DO $$
DECLARE
  seq    text := pg_get_serial_sequence('events', 'id');
  min_id bigint;
BEGIN
  -- PK index lookup: instant
  SELECT min(id) INTO min_id FROM events;

  -- Make sure ids 1 .. 1,000,000,000 (+ margin) are really free before reusing them.
  IF min_id IS NOT NULL AND min_id <= 1100000000 THEN
    RAISE EXCEPTION 'low id range not free (min(id) = %), aborting', min_id;
  END IF;

  -- next nextval() returns 1
  PERFORM setval(seq, 1, false);
END
$$;

RESET lock_timeout;
```
