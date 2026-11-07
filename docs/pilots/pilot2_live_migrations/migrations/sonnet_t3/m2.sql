-- M2
SET lock_timeout = '50ms';

-- helper CHECK so SET NOT NULL can skip the full-table scan
DO $$
BEGIN
  FOR i IN 1..150 LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_customer_id_nn CHECK (customer_id IS NOT NULL) NOT VALID;
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
      ALTER TABLE orders ADD CONSTRAINT orders_customer_id_fk
        FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF i = 150 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

RESET lock_timeout;

-- these only take SHARE UPDATE EXCLUSIVE, do not block writers
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_nn;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fk;

SET lock_timeout = '50ms';
DO $$
BEGIN
  FOR i IN 1..150 LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;  -- uses validated CHECK, no scan
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
      ALTER TABLE orders DROP CONSTRAINT orders_customer_id_nn;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF i = 150 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;
RESET lock_timeout;
