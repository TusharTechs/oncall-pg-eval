```sql
-- H5: repair orders.customer_id from legacy_customer_map, then enforce NOT NULL + validated FK.
-- Strategy:
--   * backfill in small committed batches (short row-lock hold times, forced index nested loop)
--   * FK added NOT VALID (SHARE ROW EXCLUSIVE, does not conflict with analytics' ACCESS SHARE), then VALIDATE
--   * CHECK (customer_id IS NOT NULL) NOT VALID, VALIDATE, then SET NOT NULL (scan skipped thanks to the
--     validated CHECK). Every strong lock is taken with a short lock_timeout inside a retry loop, so app
--     traffic never queues behind us for more than ~50 ms and ACCESS EXCLUSIVE is obtained in the
--     analytics job's 1-3 s gaps.

\set ON_ERROR_STOP 1

-- Fresh planner stats (no setting changes; just statistics).
ANALYZE legacy_customer_map;
ANALYZE orders;

-- 1. Backfill in batches of 2000, committing each batch.
SET enable_hashjoin = off;
SET enable_mergejoin = off;
SET enable_seqscan = off;

DO $$
DECLARE
  v_last bigint := 0;
  v_next bigint;
BEGIN
  LOOP
    SELECT max(order_id) INTO v_next
    FROM (SELECT order_id
          FROM legacy_customer_map
          WHERE order_id > v_last
          ORDER BY order_id
          LIMIT 2000) s;
    EXIT WHEN v_next IS NULL;

    UPDATE orders o
       SET customer_id = m.customer_id
      FROM legacy_customer_map m
     WHERE m.order_id > v_last
       AND m.order_id <= v_next
       AND o.id = m.order_id
       AND o.customer_id IS DISTINCT FROM m.customer_id;

    COMMIT;
    v_last := v_next;
  END LOOP;
END
$$;

RESET enable_hashjoin;
RESET enable_mergejoin;
RESET enable_seqscan;

-- 2. Foreign key, NOT VALID (SHARE ROW EXCLUSIVE on orders and customers), with short lock_timeout + retry.
DO $$
DECLARE
  i int := 0;
BEGIN
  PERFORM set_config('lock_timeout', '50ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_fkey
        FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 600 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

-- 3. Validate FK (SHARE UPDATE EXCLUSIVE on orders, ROW SHARE on customers: no conflict with app/analytics).
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey;

-- 4. Helper CHECK constraint, NOT VALID (needs ACCESS EXCLUSIVE briefly -> retry until analytics gap).
DO $$
DECLARE
  i int := 0;
BEGIN
  PERFORM set_config('lock_timeout', '50ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_not_null
        CHECK (customer_id IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 600 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

-- 5. Validate the CHECK (SHARE UPDATE EXCLUSIVE, full scan without blocking app or analytics).
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_not_null;

-- 6. SET NOT NULL: ACCESS EXCLUSIVE, but no table scan because the validated CHECK proves no NULLs.
DO $$
DECLARE
  i int := 0;
BEGIN
  PERFORM set_config('lock_timeout', '50ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 600 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

-- Helper CHECK constraint orders_customer_id_not_null is intentionally left in place
-- (dropping it would require another ACCESS EXCLUSIVE acquisition; the ticket allows it to remain).
```
