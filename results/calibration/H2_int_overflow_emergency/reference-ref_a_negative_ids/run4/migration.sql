-- Reference A: the classic emergency fix. The int4 range has 2^31 unused NEGATIVE values. Restart the identity
-- sequence at the int4 minimum and count upward: ~2.1 billion inserts of headroom, no rewrite, no id changes.
-- (The proper int -> bigint migration is then scheduled for a maintenance window.)
-- ALTER SEQUENCE only locks the sequence, not the events table, so the analytics reader does not block it.
SET lock_timeout = '50ms';
DO $$ BEGIN
  FOR i IN 1..300 LOOP BEGIN
    ALTER SEQUENCE events_id_seq MINVALUE -2147483648 RESTART WITH -2147483648; RETURN;
  EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.05); END; END LOOP;
  RAISE EXCEPTION 'could not alter sequence';
END $$;
