```sql
-- C4: orders.amount_cents bigint NOT NULL, always = (amount * 100)::bigint.
-- A STORED generated column would rewrite 5M rows under ACCESS EXCLUSIVE (blocks
-- the app for seconds), so instead:
--   1. trigger function that derives amount_cents on every INSERT/UPDATE;
--   2. (brief ACCESS EXCLUSIVE, retried) add nullable column + NOT VALID CHECK
--      (amount_cents IS NOT NULL) + trigger, atomically;
--   3. backfill existing rows in small committed batches (short row locks only);
--   4. VALIDATE the CHECK (SHARE UPDATE EXCLUSIVE, non-blocking);
--   5. (brief ACCESS EXCLUSIVE, retried) SET NOT NULL -- no scan thanks to the CHECK.

SET statement_timeout = 0;

-- 1. Trigger function (touches only NEW, so the app needs no extra table privileges)
CREATE OR REPLACE FUNCTION orders_set_amount_cents() RETURNS trigger
LANGUAGE plpgsql AS
$$
BEGIN
  NEW.amount_cents := (NEW.amount * 100)::bigint;
  RETURN NEW;
END
$$;

GRANT EXECUTE ON FUNCTION orders_set_amount_cents() TO app;

-- 2. Column + NOT VALID check + trigger in one short ACCESS EXCLUSIVE window
SET lock_timeout = '100ms';

DO $$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '30 seconds';
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN IF NOT EXISTS amount_cents bigint;
      ALTER TABLE orders
        ADD CONSTRAINT orders_amount_cents_not_null CHECK (amount_cents IS NOT NULL) NOT VALID;
      CREATE TRIGGER orders_set_amount_cents
        BEFORE INSERT OR UPDATE ON orders
        FOR EACH ROW EXECUTE FUNCTION orders_set_amount_cents();
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

-- 3. Backfill existing rows in small batches, committing after each batch so row
--    locks are held only briefly (app UPDATEs on the same rows wait < ~100 ms).
--    Only row-level locks and ROW EXCLUSIVE are needed, which nothing else conflicts with.
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
       SET amount_cents = (amount * 100)::bigint
     WHERE id >= lo AND id < lo + batch
       AND amount_cents IS NULL;
    COMMIT;
    lo := lo + batch;
  END LOOP;
END
$$;

-- Safety net: catch any straggler (e.g. ids outside the scanned range).
UPDATE orders SET amount_cents = (amount * 100)::bigint WHERE amount_cents IS NULL;

-- 4. Validate the helper CHECK (SHARE UPDATE EXCLUSIVE: does not block app or analytics)
ALTER TABLE orders VALIDATE CONSTRAINT orders_amount_cents_not_null;

-- 5. Real NOT NULL; PG uses the validated CHECK to skip the full-table scan.
SET lock_timeout = '100ms';

DO $$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '30 seconds';
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN amount_cents SET NOT NULL;
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
