-- Reference B (independent style): LOCK ... NOWAIT inside a retry function, jittered backoff.
CREATE FUNCTION pg_temp.try_add() RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
  LOCK TABLE orders IN ACCESS EXCLUSIVE MODE NOWAIT;
  ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU';
  RETURN true;
EXCEPTION WHEN lock_not_available THEN
  RETURN false;
END $$;
DO $$
BEGIN
  FOR i IN 1..300 LOOP
    IF pg_temp.try_add() THEN RETURN; END IF;
    PERFORM pg_sleep(0.1 + random() * 0.1);
  END LOOP;
  RAISE EXCEPTION 'gave up';
END $$;
