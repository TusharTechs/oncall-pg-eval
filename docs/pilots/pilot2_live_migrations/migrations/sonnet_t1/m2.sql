-- M2
SET lock_timeout = '50ms';

-- helper CHECK (brief ACCESS EXCLUSIVE, retried) so SET NOT NULL can skip the table scan
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_cust_nn_chk CHECK (customer_id IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;

-- FK added NOT VALID (no scan), retried on lock timeout
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_customer_fk
        FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;

RESET lock_timeout;

-- long scans, only SHARE UPDATE EXCLUSIVE (do not block app writes)
ALTER TABLE orders VALIDATE CONSTRAINT orders_cust_nn_chk;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_fk;

SET lock_timeout = '50ms';

-- SET NOT NULL uses the validated CHECK, so no scan under ACCESS EXCLUSIVE
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;

DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders DROP CONSTRAINT orders_cust_nn_chk;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;

RESET lock_timeout;
