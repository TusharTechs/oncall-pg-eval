```sql
-- Ticket C2: orders.customer_id NOT NULL + validated FK to customers(id)
--
-- Plan (never hold a write-blocking lock for more than a few ms, never queue
-- a strong lock behind the analytics transaction):
--   1. Add FK NOT VALID + CHECK (customer_id IS NOT NULL) NOT VALID   (brief lock, retried)
--   2. VALIDATE both                                                 (SHARE UPDATE EXCLUSIVE: no app blocking)
--   3. SET NOT NULL (uses the validated CHECK, no scan) + drop helper (brief lock, retried)

SET statement_timeout = 0;

-- Step 1
SET lock_timeout = '50ms';
DO $$
DECLARE
  attempts int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_fkey
          FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID,
        ADD CONSTRAINT orders_customer_id_not_null
          CHECK (customer_id IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      attempts := attempts + 1;
      IF attempts >= 150 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.15 + random() * 0.1);
    END;
  END LOOP;
END
$$;

-- Step 2: validation scans only take SHARE UPDATE EXCLUSIVE (orders) / ROW SHARE (customers)
RESET lock_timeout;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_not_null;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey;

-- Step 3: SET NOT NULL is proven by the validated CHECK (PG 12+), so no table scan
SET lock_timeout = '50ms';
DO $$
DECLARE
  attempts int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      ALTER TABLE orders DROP CONSTRAINT orders_customer_id_not_null;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      attempts := attempts + 1;
      IF attempts >= 150 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.15 + random() * 0.1);
    END;
  END LOOP;
END
$$;

RESET lock_timeout;
```
