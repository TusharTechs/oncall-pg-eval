-- M2: customer_id NOT NULL + validated FK to customers(id), without long blocking locks.

CREATE FUNCTION pg_temp.ddl_with_retry(VARIADIC stmts text[]) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  attempt int := 0;
  s text;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      FOREACH s IN ARRAY stmts LOOP
        EXECUTE s;
      END LOOP;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      attempt := attempt + 1;
      IF attempt >= 300 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

-- 1) FK as NOT VALID: brief SHARE ROW EXCLUSIVE on orders/customers (does not conflict
--    with the analytics ACCESS SHARE, only briefly with app writers).
SELECT pg_temp.ddl_with_retry(
  'ALTER TABLE orders ADD CONSTRAINT orders_customer_id_fkey
     FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID'
);

-- 2) Validate FK: SHARE UPDATE EXCLUSIVE only, does not block app traffic.
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey;

-- 3) Helper CHECK as NOT VALID: brief ACCESS EXCLUSIVE (waits for analytics via retries).
SELECT pg_temp.ddl_with_retry(
  'ALTER TABLE orders ADD CONSTRAINT orders_customer_id_not_null
     CHECK (customer_id IS NOT NULL) NOT VALID'
);

-- 4) Validate CHECK: SHARE UPDATE EXCLUSIVE, full scan without blocking app.
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_not_null;

-- 5) SET NOT NULL uses the validated CHECK to skip the table scan (PG12+),
--    then drop the now-redundant helper in the same short transaction.
SELECT pg_temp.ddl_with_retry(
  'ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL',
  'ALTER TABLE orders DROP CONSTRAINT orders_customer_id_not_null'
);
