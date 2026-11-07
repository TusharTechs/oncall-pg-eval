```sql
-- H2: events.id (integer identity) is ~5,000 values from overflow.
-- Converting the column to bigint rewrites the table and its PK index under
-- ACCESS EXCLUSIVE (seconds of blocked inserts), so that is deferred to a maintenance
-- window. Emergency fix now: point the identity sequence at the large unused part of the
-- integer range. All existing ids form one contiguous block just below the max, so we
-- count DOWNWARD from (min(id) - 1) to -2147483648: about 4.29 billion free values, none
-- of which can collide with an existing row. Existing ids are untouched, the column stays
-- an identity column, and the app keeps its existing USAGE grant on the same sequence.
-- ALTER SEQUENCE only takes a brief lock on the sequence (not the table), so analytics
-- readers on events don't affect it; short lock_timeout + retry so app nextval() calls
-- never queue behind us for long.
--
-- Follow-up (maintenance window): ALTER events.id (and the sequence) to bigint.

SET statement_timeout = 0;
SET lock_timeout = 0;

DO $$
DECLARE
  start_id bigint;
  deadline constant timestamptz := clock_timestamp() + interval '15 seconds';
BEGIN
  SELECT min(id) - 1 INTO start_id FROM events;
  IF start_id IS NULL OR start_id < -2147483648 + 1000000000 THEN
    RAISE EXCEPTION 'unexpected events.id layout (min-1 = %), aborting', start_id;
  END IF;

  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      EXECUTE format(
        'ALTER SEQUENCE events_id_seq INCREMENT BY -1 MINVALUE -2147483648 MAXVALUE 2147483647 RESTART WITH %s',
        start_id);
      EXIT;
    EXCEPTION WHEN lock_not_available OR deadlock_detected THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;
```
