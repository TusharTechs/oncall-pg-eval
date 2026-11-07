```sql
-- H1: orders.public_id uuid NOT NULL DEFAULT gen_random_uuid(), online.
-- ADD COLUMN ... DEFAULT gen_random_uuid() (volatile) would rewrite all 5M rows under
-- ACCESS EXCLUSIVE, blocking the app for seconds. Instead:
--   1. (brief ACCESS EXCLUSIVE, retried) add the column with no default, then SET DEFAULT
--      (applies to new rows only, no rewrite), plus a NOT VALID CHECK (public_id IS NOT NULL);
--   2. backfill existing rows in small committed batches;
--   3. VALIDATE the CHECK (SHARE UPDATE EXCLUSIVE, non-blocking);
--   4. (brief ACCESS EXCLUSIVE, retried) SET NOT NULL -- no scan thanks to the CHECK.
-- No unique index/constraint is created (per ticket).

SET statement_timeout = 0;
SET lock_timeout = '100ms';

-- 1. Column + default + NOT VALID check, all metadata-only
DO $$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '30 seconds';
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN IF NOT EXISTS public_id uuid;
      ALTER TABLE orders ALTER COLUMN public_id SET DEFAULT gen_random_uuid();
      ALTER TABLE orders
        ADD CONSTRAINT orders_public_id_not_null CHECK (public_id IS NOT NULL) NOT VALID;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

-- 2. Backfill pre-existing rows in small batches, committing each batch so row locks
--    are held only briefly. Rows inserted from now on get the column default.
SET lock_timeout = 0;

DO $$
DECLARE
  max_id bigint;
  lo     bigint := 0;
  batch  constant bigint := 10000;
BEGIN
  SELECT coalesce(max(id), 0) INTO max_id FROM orders;
  WHILE lo <= max_id LOOP
    UPDATE orders
       SET public_id = gen_random_uuid()
     WHERE id >= lo AND id < lo + batch
       AND public_id IS NULL;
    COMMIT;
    lo := lo + batch;
  END LOOP;
END
$$;

-- Safety net for any straggler outside the scanned id range.
UPDATE orders SET public_id = gen_random_uuid() WHERE public_id IS NULL;

-- 3. Validate the helper CHECK without blocking writers/readers
ALTER TABLE orders VALIDATE CONSTRAINT orders_public_id_not_null;

-- 4. Real NOT NULL (uses the validated CHECK, so no table scan under the lock)
SET lock_timeout = '100ms';

DO $$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '30 seconds';
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN public_id SET NOT NULL;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

RESET lock_timeout;
```
