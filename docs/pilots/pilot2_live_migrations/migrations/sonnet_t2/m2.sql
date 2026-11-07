-- M2
SET lock_timeout = '50ms';

-- 1. FK as NOT VALID (brief lock, retried)
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_customer_id_fkey
        FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

-- 2. Validate FK (does not block writes)
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey;

-- 3. CHECK (customer_id IS NOT NULL) as NOT VALID (brief lock, retried)
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_customer_id_nn
        CHECK (customer_id IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_nn;

-- 4. SET NOT NULL (skips scan thanks to validated CHECK; retried)
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

-- 5. Drop helper constraint (retried)
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders DROP CONSTRAINT orders_customer_id_nn;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;
