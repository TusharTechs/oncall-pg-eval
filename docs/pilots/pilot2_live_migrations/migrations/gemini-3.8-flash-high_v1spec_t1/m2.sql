SET lock_timeout = '200ms';

DO $$
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_not_null CHECK (customer_id IS NOT NULL) NOT VALID,
        ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID;
      EXIT;
    EXCEPTION
      WHEN lock_not_available OR deadlock_detected THEN
        PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END;
$$;

RESET lock_timeout;

ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_not_null;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey;

SET lock_timeout = '200ms';

DO $$
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      EXIT;
    EXCEPTION
      WHEN lock_not_available OR deadlock_detected THEN
        PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END;
$$;

RESET lock_timeout;
