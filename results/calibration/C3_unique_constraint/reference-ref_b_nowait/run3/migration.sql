-- Reference B (independent style): CIC with a statement_timeout safety net, NOWAIT attach with jittered backoff.
SET statement_timeout = '50s';
CREATE UNIQUE INDEX CONCURRENTLY ux_orders_ext ON orders (external_ref);
SET statement_timeout = 0;
CREATE FUNCTION pg_temp.attach() RETURNS boolean LANGUAGE plpgsql AS $f$
BEGIN
  LOCK TABLE orders IN ACCESS EXCLUSIVE MODE NOWAIT;
  ALTER TABLE orders ADD CONSTRAINT ux_orders_ext UNIQUE USING INDEX ux_orders_ext;
  RETURN true;
EXCEPTION WHEN lock_not_available THEN RETURN false;
END $f$;
DO $$ BEGIN
  FOR i IN 1..400 LOOP IF pg_temp.attach() THEN RETURN; END IF; PERFORM pg_sleep(0.1 + random()*0.1); END LOOP;
  RAISE EXCEPTION 'gave up';
END $$;
