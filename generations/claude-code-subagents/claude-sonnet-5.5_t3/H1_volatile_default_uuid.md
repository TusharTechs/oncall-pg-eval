```sql
CREATE FUNCTION pg_temp.ddl_retry(stmt text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  i int;
BEGIN
  FOR i IN 1..200 LOOP
    BEGIN
      SET LOCAL lock_timeout = '100ms';
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      PERFORM pg_sleep(0.15);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock for: %', stmt;
END
$f$;

-- 1. A volatile DEFAULT on ADD COLUMN would rewrite the 5M-row table under ACCESS EXCLUSIVE.
--    Instead add a plain nullable column, then set the default (both metadata-only, same txn),
--    so rows inserted from now on get a uuid automatically.
SELECT pg_temp.ddl_retry($q$
  ALTER TABLE orders ADD COLUMN public_id uuid;
  ALTER TABLE orders ALTER COLUMN public_id SET DEFAULT gen_random_uuid()
$q$);

-- 2. Backfill existing rows in small committed batches.
DO $$
DECLARE
  lo bigint := 0;
  mx bigint;
BEGIN
  SELECT max(id) INTO mx FROM orders;
  WHILE lo <= mx LOOP
    UPDATE orders
       SET public_id = gen_random_uuid()
     WHERE id > lo AND id <= lo + 10000
       AND public_id IS NULL;
    lo := lo + 10000;
    COMMIT;
  END LOOP;
END
$$;

-- 3. NOT NULL via a validated CHECK so SET NOT NULL does not scan under ACCESS EXCLUSIVE.
SELECT pg_temp.ddl_retry($q$
  ALTER TABLE orders ADD CONSTRAINT orders_public_id_nn CHECK (public_id IS NOT NULL) NOT VALID
$q$);
ALTER TABLE orders VALIDATE CONSTRAINT orders_public_id_nn;
SELECT pg_temp.ddl_retry($q$ ALTER TABLE orders ALTER COLUMN public_id SET NOT NULL $q$);
SELECT pg_temp.ddl_retry($q$ ALTER TABLE orders DROP CONSTRAINT orders_public_id_nn $q$);
```
