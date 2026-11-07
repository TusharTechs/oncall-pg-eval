DO $$
BEGIN
  LOOP
    EXIT WHEN NOT EXISTS (
      SELECT 1
      FROM pg_locks
      WHERE relation = 'orders'::regclass
        AND mode = 'AccessShareLock'
        AND pid <> pg_backend_pid()
    );
    PERFORM pg_sleep(0.1);
  END LOOP;
END $$;

SET lock_timeout = '200ms';

DO $$
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_not_null CHECK (customer_id IS NOT NULL) NOT VALID,
        ADD CONSTRAINT fk_orders_customer_id FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID;
      EXIT;
    EXCEPTION
      WHEN lock_not_available THEN
        PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;

RESET lock_timeout;

ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_not_null;
ALTER TABLE orders VALIDATE CONSTRAINT fk_orders_customer_id;

SET lock_timeout = '200ms';

DO $$
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      EXIT;
    EXCEPTION
      WHEN lock_not_available THEN
        PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;

RESET lock_timeout;
