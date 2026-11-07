```sql
-- H5: backfill orders.customer_id from legacy_customer_map, then enforce NOT NULL + validated FK.
-- Strategy:
--   1. Backfill in small committed batches (short row locks only).
--   2. Add CHECK (customer_id IS NOT NULL) NOT VALID and FK NOT VALID in one ALTER,
--      acquiring the lock with a short lock_timeout + retry (analytics holds AccessShare for 6-12s).
--   3. VALIDATE both constraints (SHARE UPDATE EXCLUSIVE only; does not block app or analytics).
--   4. SET NOT NULL with short lock_timeout + retry; the validated CHECK lets PG skip the table scan.

\set ON_ERROR_STOP 1

ANALYZE legacy_customer_map;

-- ---------------------------------------------------------------------------
-- 1. Batched backfill
-- ---------------------------------------------------------------------------
SET enable_seqscan = off;   -- session-only: force PK index lookups for small batches

DO $$
DECLARE
  last_id bigint := 0;
  next_id bigint;
BEGIN
  LOOP
    WITH batch AS MATERIALIZED (
      SELECT order_id, customer_id
      FROM legacy_customer_map
      WHERE order_id > last_id
      ORDER BY order_id
      LIMIT 5000
    ), upd AS (
      UPDATE orders o
         SET customer_id = b.customer_id
        FROM batch b
       WHERE o.id = b.order_id
         AND o.customer_id IS DISTINCT FROM b.customer_id
      RETURNING 1
    )
    SELECT max(order_id) INTO next_id FROM batch;

    EXIT WHEN next_id IS NULL;
    last_id := next_id;
    COMMIT;
  END LOOP;
END
$$;

RESET enable_seqscan;

-- ---------------------------------------------------------------------------
-- 2. Add NOT VALID CHECK + NOT VALID FK (brief ACCESS EXCLUSIVE, acquired with retry)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  attempts int := 0;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_not_null CHECK (customer_id IS NOT NULL) NOT VALID,
        ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id)
            REFERENCES customers(id) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      attempts := attempts + 1;
      IF attempts > 400 THEN
        RAISE;
      END IF;
    END;
    PERFORM pg_sleep(0.25 + random() * 0.1);
  END LOOP;
END
$$;

-- ---------------------------------------------------------------------------
-- 3. Validate (SHARE UPDATE EXCLUSIVE on orders, ROW SHARE on customers)
-- ---------------------------------------------------------------------------
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_not_null;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey;

-- ---------------------------------------------------------------------------
-- 4. SET NOT NULL (no scan thanks to validated CHECK; brief ACCESS EXCLUSIVE with retry)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  attempts int := 0;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      attempts := attempts + 1;
      IF attempts > 400 THEN
        RAISE;
      END IF;
    END;
    PERFORM pg_sleep(0.25 + random() * 0.1);
  END LOOP;
END
$$;

-- Helper CHECK constraint orders_customer_id_not_null is left in place (allowed by the ticket);
-- dropping it would need another ACCESS EXCLUSIVE lock for no benefit.
```
