-- Reference B (independent style): both NOT VALID constraints in one ALTER, one combined VALIDATE, jittered NOWAIT retries.
CREATE FUNCTION pg_temp.try(stmt text) RETURNS boolean LANGUAGE plpgsql AS $f$
BEGIN
  SET LOCAL lock_timeout = '30ms';
  EXECUTE stmt; RETURN true;
EXCEPTION WHEN lock_not_available THEN RETURN false;
END $f$;
DO $$
DECLARE steps text[] := ARRAY[
  'ALTER TABLE orders ADD CONSTRAINT c_nn CHECK (customer_id IS NOT NULL) NOT VALID, ADD CONSTRAINT c_fk FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID'];
BEGIN
  FOR i IN 1..600 LOOP EXIT WHEN pg_temp.try(steps[1]); PERFORM pg_sleep(0.15 + random()*0.1); END LOOP;
END $$;
ALTER TABLE orders VALIDATE CONSTRAINT c_nn, VALIDATE CONSTRAINT c_fk;
DO $$ BEGIN
  FOR i IN 1..600 LOOP EXIT WHEN pg_temp.try('ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL'); PERFORM pg_sleep(0.15 + random()*0.1); END LOOP;
END $$;
