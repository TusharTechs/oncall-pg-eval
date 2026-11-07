-- Reference B (independent style): column + default + NOT VALID check in ONE short ALTER (all metadata-only when the
-- column is added without a default and the default is attached afterwards in the same statement list), keyset backfill.
CREATE FUNCTION pg_temp.try(VARIADIC stmts text[]) RETURNS boolean LANGUAGE plpgsql AS $f$
DECLARE s text;
BEGIN SET LOCAL lock_timeout = '30ms'; FOREACH s IN ARRAY stmts LOOP EXECUTE s; END LOOP; RETURN true;
EXCEPTION WHEN lock_not_available THEN RETURN false; END $f$;
DO $$ BEGIN
  FOR i IN 1..600 LOOP
    IF pg_temp.try('ALTER TABLE orders ADD COLUMN public_id uuid',
                   'ALTER TABLE orders ALTER COLUMN public_id SET DEFAULT gen_random_uuid(), ADD CONSTRAINT pid_nn CHECK (public_id IS NOT NULL) NOT VALID') THEN RETURN; END IF;
    PERFORM pg_sleep(0.15 + random()*0.1);
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock';
END $$;
CREATE PROCEDURE pg_temp.backfill() LANGUAGE plpgsql AS $$
DECLARE last_id bigint := 0;
BEGIN
  LOOP
    WITH b AS (SELECT id FROM orders WHERE id > last_id ORDER BY id LIMIT 10000),
         u AS (UPDATE orders o SET public_id = gen_random_uuid() FROM b WHERE o.id = b.id AND o.public_id IS NULL RETURNING 1)
    SELECT max(b.id) INTO last_id FROM b;
    EXIT WHEN last_id IS NULL;
    COMMIT;
  END LOOP;
END $$;
CALL pg_temp.backfill();
ALTER TABLE orders VALIDATE CONSTRAINT pid_nn;
DO $$ BEGIN
  FOR i IN 1..600 LOOP IF pg_temp.try('ALTER TABLE orders ALTER COLUMN public_id SET NOT NULL') THEN RETURN; END IF; PERFORM pg_sleep(0.15 + random()*0.1); END LOOP;
  RAISE EXCEPTION 'could not acquire lock';
END $$;
