```sql
-- C4: orders.amount_cents bigint NOT NULL = (amount * 100)::bigint, kept in sync by trigger.
-- Plan:
--   1. Trigger function (no lock on orders).
--   2. One short ACCESS EXCLUSIVE window (lock_timeout + retry, to slip between analytics
--      transactions): add nullable column (metadata only), add CHECK (amount_cents IS NOT NULL)
--      NOT VALID, create the BEFORE INSERT OR UPDATE trigger. From this moment every new or
--      updated row gets the correct value, and the CHECK enforces non-NULL for them.
--   3. Backfill existing rows in small committed batches (short row locks only).
--   4. VALIDATE the CHECK (SHARE UPDATE EXCLUSIVE, does not block app DML).
--   5. Second short window: SET NOT NULL (scan skipped thanks to the validated CHECK),
--      then drop the redundant helper CHECK.

SET statement_timeout = 0;
SET lock_timeout = 0;

CREATE FUNCTION orders_set_amount_cents() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.amount_cents := (NEW.amount * 100)::bigint;
  RETURN NEW;
END
$$;

DO $$
DECLARE
  deadline constant timestamptz := clock_timestamp() + interval '30 seconds';
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN amount_cents bigint;
      ALTER TABLE orders
        ADD CONSTRAINT orders_amount_cents_not_null CHECK (amount_cents IS NOT NULL) NOT VALID;
      CREATE TRIGGER orders_amount_cents_sync
        BEFORE INSERT OR UPDATE ON orders
        FOR EACH ROW EXECUTE FUNCTION orders_set_amount_cents();
      EXIT;
    EXCEPTION WHEN lock_not_available OR deadlock_detected THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;

-- Backfill: every row that existed before the trigger has id <= max(id) read now.
DO $$
DECLARE
  lo    bigint;
  maxid bigint;
  step  constant bigint := 10000;
BEGIN
  SELECT min(id), max(id) INTO lo, maxid FROM orders;
  IF lo IS NULL THEN
    RETURN;
  END IF;
  WHILE lo <= maxid LOOP
    UPDATE orders
       SET amount_cents = (amount * 100)::bigint
     WHERE id >= lo AND id < lo + step
       AND amount_cents IS NULL;
    COMMIT;
    lo := lo + step;
  END LOOP;
END
$$;

ALTER TABLE orders VALIDATE CONSTRAINT orders_amount_cents_not_null;

DO $$
DECLARE
  deadline constant timestamptz := clock_timestamp() + interval '30 seconds';
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN amount_cents SET NOT NULL;
      ALTER TABLE orders DROP CONSTRAINT orders_amount_cents_not_null;
      EXIT;
    EXCEPTION WHEN lock_not_available OR deadlock_detected THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;
```
