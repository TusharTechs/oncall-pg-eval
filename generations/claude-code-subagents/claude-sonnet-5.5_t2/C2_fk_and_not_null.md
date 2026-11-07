```sql
-- Step 1: add FK and a helper CHECK as NOT VALID (brief lock, no scan). Retry with short lock_timeout.
SET lock_timeout = '50ms';

DO $$
DECLARE
  i int;
BEGIN
  FOR i IN 1..150 LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_fk FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID,
        ADD CONSTRAINT orders_customer_id_nn CHECK (customer_id IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF i = 150 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;

RESET lock_timeout;

-- Step 2: validate without blocking writes (SHARE UPDATE EXCLUSIVE).
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fk;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_nn;

-- Step 3: SET NOT NULL uses the validated CHECK to skip the scan; drop the helper afterwards.
SET lock_timeout = '50ms';

DO $$
DECLARE
  i int;
BEGIN
  FOR i IN 1..150 LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      ALTER TABLE orders DROP CONSTRAINT orders_customer_id_nn;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF i = 150 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;

RESET lock_timeout;
```
