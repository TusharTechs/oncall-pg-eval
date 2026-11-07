-- Reference B (independent style): build under a NEW name, attach it, then drop every leftover invalid index concurrently.
SET statement_timeout = 0;
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_uq ON orders (external_ref);
CREATE FUNCTION pg_temp.attach() RETURNS boolean LANGUAGE plpgsql AS $f$
BEGIN LOCK TABLE orders IN ACCESS EXCLUSIVE MODE NOWAIT;
  ALTER TABLE orders ADD CONSTRAINT orders_external_ref_uq UNIQUE USING INDEX orders_external_ref_uq; RETURN true;
EXCEPTION WHEN lock_not_available THEN RETURN false; END $f$;
DO $$ BEGIN FOR i IN 1..400 LOOP IF pg_temp.attach() THEN RETURN; END IF; PERFORM pg_sleep(0.1 + random()*0.1); END LOOP;
  RAISE EXCEPTION 'gave up'; END $$;
SELECT format('DROP INDEX CONCURRENTLY IF EXISTS %I', c.relname)
  FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE i.indrelid = 'orders'::regclass AND NOT i.indisvalid \gexec
