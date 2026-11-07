```sql
-- Helper: run a DDL statement needing a strong lock with a short lock_timeout,
-- retrying so we never sit in the lock queue (and block the app) behind analytics.
CREATE FUNCTION pg_temp.ddl_retry(stmt text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  i int;
BEGIN
  FOR i IN 1..200 LOOP
    BEGIN
      SET LOCAL lock_timeout = '100ms';
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      PERFORM pg_sleep(0.15);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock for: %', stmt;
END
$f$;

-- 1. Add FK and a helper CHECK as NOT VALID (instant, no scan).
SELECT pg_temp.ddl_retry($q$
  ALTER TABLE orders
    ADD CONSTRAINT orders_customer_id_fk FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID,
    ADD CONSTRAINT orders_customer_id_nn CHECK (customer_id IS NOT NULL) NOT VALID
$q$);

-- 2. Validate without blocking writes (SHARE UPDATE EXCLUSIVE).
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fk;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_nn;

-- 3. SET NOT NULL skips the table scan because the validated CHECK proves it.
SELECT pg_temp.ddl_retry($q$ ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL $q$);

-- 4. Drop the helper constraint.
SELECT pg_temp.ddl_retry($q$ ALTER TABLE orders DROP CONSTRAINT orders_customer_id_nn $q$);
```
