-- M4
SET lock_timeout = '50ms';

DO $$
BEGIN
  FOR i IN 1..150 LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN amount_cents bigint;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF i = 150 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION orders_set_amount_cents() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.amount_cents := (NEW.amount * 100)::bigint;
  RETURN NEW;
END $$;

DO $$
BEGIN
  FOR i IN 1..150 LOOP
    BEGIN
      CREATE TRIGGER orders_amount_cents_trg
        BEFORE INSERT OR UPDATE OF amount, amount_cents ON orders
        FOR EACH ROW EXECUTE FUNCTION orders_set_amount_cents();
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF i = 150 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

RESET lock_timeout;

-- batched backfill, commit per batch so row locks are short-lived
DO $$
DECLARE
  lo bigint;
  hi bigint;
  mx bigint;
BEGIN
  SELECT coalesce(min(id), 0), coalesce(max(id), 0) INTO lo, mx FROM orders;
  WHILE lo <= mx LOOP
    hi := lo + 4999;
    UPDATE orders
       SET amount_cents = (amount * 100)::bigint
     WHERE id >= lo AND id <= hi AND amount_cents IS NULL;
    COMMIT;
    lo := hi + 1;
    PERFORM pg_sleep(0.005);
  END LOOP;
END $$;

SET lock_timeout = '50ms';

DO $$
BEGIN
  FOR i IN 1..150 LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_amount_cents_nn CHECK (amount_cents IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF i = 150 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

RESET lock_timeout;
ALTER TABLE orders VALIDATE CONSTRAINT orders_amount_cents_nn;
SET lock_timeout = '50ms';

DO $$
BEGIN
  FOR i IN 1..150 LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN amount_cents SET NOT NULL;  -- no scan thanks to validated CHECK
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF i = 150 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

DO $$
BEGIN
  FOR i IN 1..150 LOOP
    BEGIN
      ALTER TABLE orders DROP CONSTRAINT orders_amount_cents_nn;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF i = 150 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;
RESET lock_timeout;
