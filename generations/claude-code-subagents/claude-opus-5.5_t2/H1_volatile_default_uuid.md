```sql
-- Ticket H1: orders.public_id uuid NOT NULL DEFAULT gen_random_uuid()
--
-- ADD COLUMN ... DEFAULT gen_random_uuid() (volatile) would rewrite all 5M rows
-- under ACCESS EXCLUSIVE -> app outage. Instead:
--   1. Brief ACCESS EXCLUSIVE step (retried, short lock_timeout):
--        add nullable column, set the default (applies to new rows only),
--        add CHECK (public_id IS NOT NULL) NOT VALID, and a temporary trigger
--        that fills public_id if an app UPDATE touches a not-yet-backfilled row
--        (otherwise the NOT VALID check would reject that UPDATE).
--   2. Backfill existing rows in small committed batches.
--   3. VALIDATE the CHECK (SHARE UPDATE EXCLUSIVE, non-blocking).
--   4. Brief ACCESS EXCLUSIVE step (retried): SET NOT NULL (proven by the CHECK,
--      no scan), drop helper CHECK and temporary trigger.

SET statement_timeout = 0;

CREATE OR REPLACE FUNCTION orders_fill_public_id() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.public_id := gen_random_uuid();
  RETURN NEW;
END
$$;
GRANT EXECUTE ON FUNCTION orders_fill_public_id() TO app;

-- 1.
SET lock_timeout = '50ms';
DO $$
DECLARE
  attempts int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN public_id uuid;
      ALTER TABLE orders
        ALTER COLUMN public_id SET DEFAULT gen_random_uuid(),
        ADD CONSTRAINT orders_public_id_not_null CHECK (public_id IS NOT NULL) NOT VALID;
      CREATE TRIGGER orders_fill_public_id
        BEFORE INSERT OR UPDATE ON orders
        FOR EACH ROW
        WHEN (NEW.public_id IS NULL)
        EXECUTE FUNCTION orders_fill_public_id();
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      attempts := attempts + 1;
      IF attempts >= 120 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.15 + random() * 0.1);
    END;
  END LOOP;
END
$$;
RESET lock_timeout;

-- 2. Backfill (every row that can still be NULL has id <= max(id) seen now)
DO $$
DECLARE
  max_id bigint;
  lo     bigint := 0;
  batch  constant bigint := 20000;
BEGIN
  SELECT max(id) INTO max_id FROM orders;
  WHILE lo < max_id LOOP
    UPDATE orders
       SET public_id = gen_random_uuid()
     WHERE id > lo AND id <= lo + batch
       AND public_id IS NULL;
    lo := lo + batch;
    COMMIT;
  END LOOP;
END
$$;

-- 3.
ALTER TABLE orders VALIDATE CONSTRAINT orders_public_id_not_null;

-- 4.
SET lock_timeout = '50ms';
DO $$
DECLARE
  attempts int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN public_id SET NOT NULL;
      ALTER TABLE orders DROP CONSTRAINT orders_public_id_not_null;
      DROP TRIGGER orders_fill_public_id ON orders;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      attempts := attempts + 1;
      IF attempts >= 120 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.15 + random() * 0.1);
    END;
  END LOOP;
END
$$;
RESET lock_timeout;

DROP FUNCTION orders_fill_public_id();
```
