-- M4
SET lock_timeout = '50ms';

CREATE OR REPLACE FUNCTION orders_set_amount_cents() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.amount_cents := (NEW.amount * 100)::bigint;
  RETURN NEW;
END $$;

-- 1. Add column and trigger atomically so no row can be missed (retried on lock timeout)
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN amount_cents bigint;
      CREATE TRIGGER orders_amount_cents_trg
        BEFORE INSERT OR UPDATE ON orders
        FOR EACH ROW EXECUTE FUNCTION orders_set_amount_cents();
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

-- 2. Batched backfill, committing per batch; row-lock waits must not hit lock_timeout
SET lock_timeout = 0;
DO $$
DECLARE
  lo bigint;
  hi bigint;
BEGIN
  SELECT min(id), max(id) INTO lo, hi FROM orders;
  WHILE lo <= hi LOOP
    UPDATE orders
       SET amount_cents = (amount * 100)::bigint
     WHERE id >= lo AND id < lo + 5000
       AND amount_cents IS NULL;
    COMMIT;
    lo := lo + 5000;
  END LOOP;
END $$;

-- 3. NOT NULL via validated CHECK
SET lock_timeout = '50ms';
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_amount_cents_nn
        CHECK (amount_cents IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

ALTER TABLE orders VALIDATE CONSTRAINT orders_amount_cents_nn;

DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN amount_cents SET NOT NULL;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders DROP CONSTRAINT orders_amount_cents_nn;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;
