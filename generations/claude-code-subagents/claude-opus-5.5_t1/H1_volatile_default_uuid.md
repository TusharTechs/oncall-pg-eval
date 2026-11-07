```sql
-- H1: orders.public_id uuid NOT NULL DEFAULT gen_random_uuid()
-- ADD COLUMN with a volatile default rewrites the whole table under ACCESS EXCLUSIVE
-- (seconds of blocked app traffic), so instead:
--   1. Short ACCESS EXCLUSIVE window (lock_timeout + retry, to slip between analytics
--      transactions): add the column with no default (metadata only), then SET DEFAULT as a
--      separate statement (applies only to future inserts, no rewrite), add a
--      CHECK (public_id IS NOT NULL) NOT VALID, and a temporary trigger that fills NULL
--      public_id on any row the app updates before the backfill reaches it (WHEN clause, so
--      it costs nothing for rows that already have a value).
--   2. Backfill in small committed batches.
--   3. VALIDATE the CHECK (SHARE UPDATE EXCLUSIVE, app DML continues).
--   4. Second short window: SET NOT NULL (scan skipped via the validated CHECK), drop the
--      helper CHECK and the temporary trigger.

SET statement_timeout = 0;
SET lock_timeout = 0;

CREATE FUNCTION orders_fill_public_id() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.public_id := gen_random_uuid();
  RETURN NEW;
END
$$;

DO $$
DECLARE
  deadline constant timestamptz := clock_timestamp() + interval '25 seconds';
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN public_id uuid;
      ALTER TABLE orders ALTER COLUMN public_id SET DEFAULT gen_random_uuid();
      ALTER TABLE orders
        ADD CONSTRAINT orders_public_id_not_null CHECK (public_id IS NOT NULL) NOT VALID;
      CREATE TRIGGER orders_public_id_fill
        BEFORE INSERT OR UPDATE ON orders
        FOR EACH ROW
        WHEN (NEW.public_id IS NULL)
        EXECUTE FUNCTION orders_fill_public_id();
      EXIT;
    EXCEPTION WHEN lock_not_available OR deadlock_detected THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;

-- Backfill: every row lacking a value has id <= max(id) read now (later inserts get the default).
DO $$
DECLARE
  lo    bigint;
  maxid bigint;
  step  constant bigint := 20000;
BEGIN
  SELECT min(id), max(id) INTO lo, maxid FROM orders;
  IF lo IS NULL THEN
    RETURN;
  END IF;
  WHILE lo <= maxid LOOP
    UPDATE orders
       SET public_id = gen_random_uuid()
     WHERE id >= lo AND id < lo + step
       AND public_id IS NULL;
    COMMIT;
    lo := lo + step;
  END LOOP;
END
$$;

ALTER TABLE orders VALIDATE CONSTRAINT orders_public_id_not_null;

DO $$
DECLARE
  deadline constant timestamptz := clock_timestamp() + interval '25 seconds';
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN public_id SET NOT NULL;
      ALTER TABLE orders DROP CONSTRAINT orders_public_id_not_null;
      DROP TRIGGER orders_public_id_fill ON orders;
      EXIT;
    EXCEPTION WHEN lock_not_available OR deadlock_detected THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;

DROP FUNCTION orders_fill_public_id();
```
