-- Reference B (independent style): count DOWN from -1 instead (also ~2.1 billion values), via the identity syntax.
-- ALTER TABLE ... ALTER COLUMN ... SET takes ACCESS EXCLUSIVE on events, so use a short lock wait with NOWAIT retries.
CREATE FUNCTION pg_temp.try() RETURNS boolean LANGUAGE plpgsql AS $f$
BEGIN
  LOCK TABLE events IN ACCESS EXCLUSIVE MODE NOWAIT;
  ALTER TABLE events ALTER COLUMN id SET INCREMENT BY -1 SET MINVALUE -2147483648 SET MAXVALUE 2147483647 RESTART WITH -1;
  RETURN true;
EXCEPTION WHEN lock_not_available THEN RETURN false; END $f$;
DO $$ BEGIN FOR i IN 1..400 LOOP IF pg_temp.try() THEN RETURN; END IF; PERFORM pg_sleep(0.1 + random()*0.1); END LOOP;
  RAISE EXCEPTION 'gave up'; END $$;
