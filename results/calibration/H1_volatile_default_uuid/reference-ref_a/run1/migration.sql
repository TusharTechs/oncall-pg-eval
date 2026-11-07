-- Reference A. A volatile default (gen_random_uuid()) is NOT the PG11+ fast path: ADD COLUMN ... DEFAULT gen_random_uuid()
-- rewrites all 5M rows under ACCESS EXCLUSIVE. Instead: add the column with no default (metadata only), then SET DEFAULT
-- (metadata only; affects only future inserts), backfill in committed batches, then NOT NULL via a validated CHECK.
SET lock_timeout = '50ms';
CREATE FUNCTION pg_temp.retry(stmt text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  FOR i IN 1..600 LOOP
    BEGIN EXECUTE stmt; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock: %', stmt;
END $$;
SELECT pg_temp.retry('ALTER TABLE orders ADD COLUMN public_id uuid');
SELECT pg_temp.retry('ALTER TABLE orders ALTER COLUMN public_id SET DEFAULT gen_random_uuid()');
DO $$
DECLARE lo bigint := 0; mx bigint;
BEGIN
  SELECT max(id) INTO mx FROM orders;
  WHILE lo <= mx LOOP
    UPDATE orders SET public_id = gen_random_uuid() WHERE id > lo AND id <= lo + 20000 AND public_id IS NULL;
    lo := lo + 20000;
    COMMIT;
  END LOOP;
END $$;
SELECT pg_temp.retry('ALTER TABLE orders ADD CONSTRAINT orders_public_id_nn CHECK (public_id IS NOT NULL) NOT VALID');
SET lock_timeout = 0;
ALTER TABLE orders VALIDATE CONSTRAINT orders_public_id_nn;
SET lock_timeout = '50ms';
SELECT pg_temp.retry('ALTER TABLE orders ALTER COLUMN public_id SET NOT NULL');
SELECT pg_temp.retry('ALTER TABLE orders DROP CONSTRAINT orders_public_id_nn');
