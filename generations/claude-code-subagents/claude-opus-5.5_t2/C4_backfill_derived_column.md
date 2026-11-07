```sql
-- Ticket C4: orders.amount_cents bigint NOT NULL, always = (amount * 100)::bigint
--
--   1. Trigger function that computes amount_cents.
--   2. One brief ACCESS EXCLUSIVE step (retried with short lock_timeout):
--        add nullable column + CHECK (amount_cents IS NOT NULL) NOT VALID + trigger.
--      From this commit on, every insert/update produces a correct amount_cents.
--   3. Backfill existing rows in small committed batches (short row locks).
--   4. VALIDATE the CHECK (SHARE UPDATE EXCLUSIVE, doesn't block the app).
--   5. Brief ACCESS EXCLUSIVE step (retried): SET NOT NULL (proven by the CHECK,
--      no scan) and drop the helper CHECK. The trigger stays to keep the
--      invariant for future inserts and amount updates.

SET statement_timeout = 0;

-- 1. Trigger function
CREATE OR REPLACE FUNCTION orders_sync_amount_cents() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.amount_cents := (NEW.amount * 100)::bigint;
  RETURN NEW;
END
$$;
GRANT EXECUTE ON FUNCTION orders_sync_amount_cents() TO app;

-- 2. Column + NOT VALID check + trigger, atomically
SET lock_timeout = '50ms';
DO $$
DECLARE
  attempts int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders
        ADD COLUMN amount_cents bigint,
        ADD CONSTRAINT orders_amount_cents_not_null CHECK (amount_cents IS NOT NULL) NOT VALID;
      CREATE TRIGGER orders_sync_amount_cents
        BEFORE INSERT OR UPDATE ON orders
        FOR EACH ROW
        WHEN (NEW.amount_cents IS DISTINCT FROM (NEW.amount * 100)::bigint)
        EXECUTE FUNCTION orders_sync_amount_cents();
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      attempts := attempts + 1;
      IF attempts >= 150 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.15 + random() * 0.1);
    END;
  END LOOP;
END
$$;
RESET lock_timeout;

-- 3. Backfill in small batches, committing each one
DO $$
DECLARE
  max_id bigint;
  lo     bigint := 0;
  batch  constant bigint := 10000;
BEGIN
  SELECT max(id) INTO max_id FROM orders;
  WHILE lo < max_id LOOP
    UPDATE orders
       SET amount_cents = (amount * 100)::bigint
     WHERE id > lo AND id <= lo + batch
       AND amount_cents IS DISTINCT FROM (amount * 100)::bigint;
    lo := lo + batch;
    COMMIT;
  END LOOP;
END
$$;

-- 4. Validate (scan under SHARE UPDATE EXCLUSIVE; app keeps running)
ALTER TABLE orders VALIDATE CONSTRAINT orders_amount_cents_not_null;

-- 5. SET NOT NULL without a scan, drop helper CHECK
SET lock_timeout = '50ms';
DO $$
DECLARE
  attempts int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN amount_cents SET NOT NULL;
      ALTER TABLE orders DROP CONSTRAINT orders_amount_cents_not_null;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      attempts := attempts + 1;
      IF attempts >= 150 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.15 + random() * 0.1);
    END;
  END LOOP;
END
$$;
RESET lock_timeout;
```
