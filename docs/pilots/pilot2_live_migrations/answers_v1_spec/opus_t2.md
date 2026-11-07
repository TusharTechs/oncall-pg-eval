```sql
-- M1: add orders.region text NOT NULL DEFAULT 'EU'
-- PG11+ stores a constant default as attmissingval: no table rewrite and no
-- NOT NULL verification scan, so the ACCESS EXCLUSIVE lock is held only for
-- the catalog update. The only danger is the lock queue (analytics txn may
-- hold ACCESS SHARE for up to 10 s), so acquire with a short lock_timeout and
-- retry, never letting app transactions queue behind us for long.
SET lock_timeout = '50ms';
SET statement_timeout = 0;

DO $$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '40 seconds';
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU';
      EXIT;
    EXCEPTION WHEN lock_not_available OR deadlock_detected THEN
      IF clock_timestamp() > deadline THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.2 + random() * 0.1);
    END;
  END LOOP;
END
$$;

RESET lock_timeout;
```

```sql
-- M2: orders.customer_id NOT NULL + validated FK to customers(id)
SET statement_timeout = 0;

-- Step 1: add FK and helper CHECK as NOT VALID (catalog-only, no scan).
-- Brief strong lock -> short lock_timeout with retry.
SET lock_timeout = '50ms';

DO $$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '15 seconds';
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_fkey
          FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID,
        ADD CONSTRAINT orders_customer_id_not_null
          CHECK (customer_id IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available OR deadlock_detected THEN
      IF clock_timestamp() > deadline THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.2 + random() * 0.1);
    END;
  END LOOP;
END
$$;

-- Step 2: validate both constraints. VALIDATE CONSTRAINT takes only
-- SHARE UPDATE EXCLUSIVE on orders (ROW SHARE on customers), which does not
-- conflict with the app's ROW EXCLUSIVE or analytics' ACCESS SHARE, so the
-- full scans run without blocking traffic. No lock_timeout here (a running
-- autovacuum would be auto-cancelled after deadlock_timeout).
SET lock_timeout = 0;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_not_null;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey;

-- Step 3: SET NOT NULL. Because a validated CHECK (customer_id IS NOT NULL)
-- exists, PG12+ skips the verification scan, so the ACCESS EXCLUSIVE lock is
-- held only for the catalog update. Short lock_timeout with retry again.
SET lock_timeout = '50ms';

DO $$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '20 seconds';
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      EXIT;
    EXCEPTION WHEN lock_not_available OR deadlock_detected THEN
      IF clock_timestamp() > deadline THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.2 + random() * 0.1);
    END;
  END LOOP;
END
$$;

-- The helper CHECK constraint orders_customer_id_not_null is intentionally
-- left in place (now redundant with attnotnull). It can be dropped later in a
-- quiet window with the same lock_timeout+retry pattern; it must NOT be dropped
-- in the same ALTER as SET NOT NULL, or the NOT NULL check would rescan.

RESET lock_timeout;
```

```sql
-- M3: UNIQUE constraint on orders(external_ref)
SET statement_timeout = 0;
SET maintenance_work_mem = '1GB';

-- Step 1: build the unique index without blocking writes.
-- CIC takes SHARE UPDATE EXCLUSIVE (no conflict with app writes or analytics
-- reads). Its internal waits for older transactions/snapshots are lock waits,
-- so lock_timeout MUST be 0 or it would abort and leave an INVALID index.
-- Cannot run inside a transaction/DO block; psql autocommit is fine.
SET lock_timeout = 0;
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders (external_ref);

-- Step 2: attach the index as a UNIQUE constraint (catalog-only, no scan).
-- Brief ACCESS EXCLUSIVE lock -> short lock_timeout with retry.
SET lock_timeout = '50ms';

DO $$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '25 seconds';
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key;
      EXIT;
    EXCEPTION WHEN lock_not_available OR deadlock_detected THEN
      IF clock_timestamp() > deadline THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.2 + random() * 0.1);
    END;
  END LOOP;
END
$$;

RESET lock_timeout;
RESET maintenance_work_mem;
```
