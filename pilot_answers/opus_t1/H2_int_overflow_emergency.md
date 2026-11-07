```sql
-- H2: events.id (int) identity sequence is ~5,000 values from 2^31-1.
-- Emergency fix: move the sequence into the completely unused negative int range.
-- -2147483648 .. 0 gives ~2.147 billion fresh ids (>= 1e9), no collisions with the
-- existing ids (all just below 2^31-1), and no existing row changes.
-- ALTER SEQUENCE locks only the sequence (not the events table), so it does not
-- queue behind the analytics transaction on events; it only waits for in-flight
-- app transactions that called nextval (milliseconds). Short lock_timeout + retry
-- keeps app latency bounded anyway.
-- The int -> bigint column conversion is deferred to a maintenance window.

SET statement_timeout = 0;
SET lock_timeout = '200ms';

DO $$
DECLARE n int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER SEQUENCE public.events_id_seq
        MINVALUE -2147483648
        RESTART WITH -2147483648;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      n := n + 1;
      IF n >= 50 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;

RESET lock_timeout;

-- Sanity check (read-only).
SELECT seqmin, seqmax, seqincrement FROM pg_sequence WHERE seqrelid = 'public.events_id_seq'::regclass;
```
