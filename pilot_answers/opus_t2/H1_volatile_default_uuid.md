```sql
-- H1: orders.public_id uuid NOT NULL DEFAULT gen_random_uuid(), without a table rewrite
-- and without blocking the app for more than a few ms at a time.
SET statement_timeout = 0;
SET lock_timeout = '100ms';

-- Step 1: add the column nullable (metadata-only) and attach the volatile default
-- (applies only to future inserts). Both in one short ACCESS EXCLUSIVE window,
-- retried with a short lock_timeout so we never queue the app behind the analytics txn.
DO $$
DECLARE attempts int := 0;
BEGIN
  LOOP
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_attribute
                     WHERE attrelid = 'orders'::regclass AND attname = 'public_id' AND NOT attisdropped) THEN
        ALTER TABLE orders ADD COLUMN public_id uuid;
      END IF;
      ALTER TABLE orders ALTER COLUMN public_id SET DEFAULT gen_random_uuid();
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      attempts := attempts + 1;
      IF attempts >= 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05 + random() * 0.15);
    END;
  END LOOP;
END $$;

-- Step 2: backfill existing rows in small committed batches (short row-lock hold times).
-- Every row inserted after step 1 already has a value from the default, and no row
-- without a value can have an id above the max(id) read here.
SET lock_timeout = '5s';
DO $$
DECLARE
  lo   bigint;
  hi   bigint;
  step constant bigint := 5000;
BEGIN
  SELECT min(id), max(id) INTO lo, hi FROM orders;
  IF lo IS NULL THEN RETURN; END IF;
  WHILE lo <= hi LOOP
    EXECUTE format(
      'UPDATE orders SET public_id = gen_random_uuid() WHERE id >= %s AND id < %s AND public_id IS NULL',
      lo, lo + step);
    COMMIT;
    lo := lo + step;
  END LOOP;
END $$;

-- Step 3: add a NOT VALID check constraint (brief ACCESS EXCLUSIVE, retried).
SET lock_timeout = '100ms';
DO $$
DECLARE attempts int := 0;
BEGIN
  LOOP
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_constraint
                     WHERE conrelid = 'orders'::regclass AND conname = 'orders_public_id_not_null') THEN
        ALTER TABLE orders ADD CONSTRAINT orders_public_id_not_null CHECK (public_id IS NOT NULL) NOT VALID;
      END IF;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      attempts := attempts + 1;
      IF attempts >= 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05 + random() * 0.15);
    END;
  END LOOP;
END $$;

-- Step 4: validate it under SHARE UPDATE EXCLUSIVE (does not block app reads/writes).
SET lock_timeout = '5s';
ALTER TABLE orders VALIDATE CONSTRAINT orders_public_id_not_null;

-- Step 5: SET NOT NULL (no scan: proven by the valid CHECK) and drop the helper CHECK,
-- in one brief ACCESS EXCLUSIVE window, retried.
SET lock_timeout = '100ms';
DO $$
DECLARE attempts int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN public_id SET NOT NULL;
      ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_public_id_not_null;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      attempts := attempts + 1;
      IF attempts >= 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05 + random() * 0.15);
    END;
  END LOOP;
END $$;

RESET lock_timeout;
```
