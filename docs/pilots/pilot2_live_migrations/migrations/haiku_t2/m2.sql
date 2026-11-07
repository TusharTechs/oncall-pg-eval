-- M2: orders.customer_id NOT NULL + validated FK to customers(id)
SET lock_timeout = '100ms';

CREATE FUNCTION pg_temp.retry_ddl(stmt text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '30 seconds';
BEGIN
  LOOP
    BEGIN
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() >= deadline THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

-- NOT VALID check + VALIDATE (SHARE UPDATE EXCLUSIVE, does not block DML) lets SET NOT NULL skip the full-table scan
SELECT pg_temp.retry_ddl('ALTER TABLE orders ADD CONSTRAINT orders_customer_id_not_null CHECK (customer_id IS NOT NULL) NOT VALID');
SELECT pg_temp.retry_ddl('ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_not_null');
SELECT pg_temp.retry_ddl('ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL');

-- FK added NOT VALID (brief lock), then validated without blocking app writes
SELECT pg_temp.retry_ddl('ALTER TABLE orders ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers (id) NOT VALID');
SELECT pg_temp.retry_ddl('ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey');

SELECT pg_temp.retry_ddl('ALTER TABLE orders DROP CONSTRAINT orders_customer_id_not_null');
