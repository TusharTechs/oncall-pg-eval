```sql
-- M1: add orders.region text NOT NULL DEFAULT 'EU' without long ACCESS EXCLUSIVE holds.
-- Strategy: every ACCESS EXCLUSIVE step is metadata-only and is retried with a short
-- lock_timeout (so app transactions never queue behind us for more than ~100 ms);
-- the only full-table scan (CHECK validation) runs under SHARE UPDATE EXCLUSIVE.
SET lock_timeout = '30s';   -- for non-retried statements; retry blocks override locally
DO $$ BEGIN
  PERFORM set_config('migr.deadline', (clock_timestamp() + interval '43 seconds')::text, false);
END $$;

-- Step 1: add nullable column with constant (fast, no rewrite) default + NOT VALID check.
DO $$
DECLARE
  deadline timestamptz := current_setting('migr.deadline')::timestamptz;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    -- Don't even try while a long-running transaction (e.g. analytics) holds a lock on orders.
    PERFORM pg_stat_clear_snapshot();
    IF EXISTS (SELECT 1
                 FROM pg_locks l JOIN pg_stat_activity a ON a.pid = l.pid
                WHERE l.locktype = 'relation' AND l.relation = 'orders'::regclass
                  AND l.granted AND l.pid <> pg_backend_pid()
                  AND a.xact_start < clock_timestamp() - interval '250 milliseconds') THEN
      IF clock_timestamp() > deadline THEN
        RAISE EXCEPTION 'M1 step 1: could not acquire lock on orders before deadline';
      END IF;
      PERFORM pg_sleep(0.02);
      CONTINUE;
    END IF;
    BEGIN
      ALTER TABLE orders
        ADD COLUMN region text DEFAULT 'EU',
        ADD CONSTRAINT orders_region_nn_chk CHECK (region IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.05 + random() * 0.10);
    END;
  END LOOP;
END $$;

-- Step 2: validate (full scan) under SHARE UPDATE EXCLUSIVE: does not block app DML or readers.
ALTER TABLE orders VALIDATE CONSTRAINT orders_region_nn_chk;

-- Step 3: SET NOT NULL (scan skipped thanks to the validated CHECK) and drop the helper check.
DO $$
DECLARE
  deadline timestamptz := current_setting('migr.deadline')::timestamptz;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    PERFORM pg_stat_clear_snapshot();
    IF EXISTS (SELECT 1
                 FROM pg_locks l JOIN pg_stat_activity a ON a.pid = l.pid
                WHERE l.locktype = 'relation' AND l.relation = 'orders'::regclass
                  AND l.granted AND l.pid <> pg_backend_pid()
                  AND a.xact_start < clock_timestamp() - interval '250 milliseconds') THEN
      IF clock_timestamp() > deadline THEN
        RAISE EXCEPTION 'M1 step 3: could not acquire lock on orders before deadline';
      END IF;
      PERFORM pg_sleep(0.02);
      CONTINUE;
    END IF;
    BEGIN
      ALTER TABLE orders ALTER COLUMN region SET NOT NULL;
      ALTER TABLE orders DROP CONSTRAINT orders_region_nn_chk;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.05 + random() * 0.10);
    END;
  END LOOP;
END $$;
```

```sql
-- M2: orders.customer_id NOT NULL + validated FK to customers(id), online.
-- Strategy: add CHECK (customer_id IS NOT NULL) and FK as NOT VALID (brief lock, retried with
-- short lock_timeout), validate both under SHARE UPDATE EXCLUSIVE (non-blocking), then
-- SET NOT NULL (no scan because of the validated CHECK) and drop the helper CHECK.
SET lock_timeout = '30s';            -- for non-retried statements; retry blocks override locally
SET maintenance_work_mem = '1GB';    -- RI validation query uses this as work_mem
DO $$ BEGIN
  PERFORM set_config('migr.deadline', (clock_timestamp() + interval '43 seconds')::text, false);
END $$;

-- Step 1: NOT VALID constraints (metadata only; enforced for new rows immediately).
DO $$
DECLARE
  deadline timestamptz := current_setting('migr.deadline')::timestamptz;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    PERFORM pg_stat_clear_snapshot();
    IF EXISTS (SELECT 1
                 FROM pg_locks l JOIN pg_stat_activity a ON a.pid = l.pid
                WHERE l.locktype = 'relation' AND l.relation = 'orders'::regclass
                  AND l.granted AND l.pid <> pg_backend_pid()
                  AND a.xact_start < clock_timestamp() - interval '250 milliseconds') THEN
      IF clock_timestamp() > deadline THEN
        RAISE EXCEPTION 'M2 step 1: could not acquire lock on orders before deadline';
      END IF;
      PERFORM pg_sleep(0.02);
      CONTINUE;
    END IF;
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_customer_id_nn_chk CHECK (customer_id IS NOT NULL) NOT VALID,
        ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id)
            REFERENCES customers(id) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.05 + random() * 0.10);
    END;
  END LOOP;
END $$;

-- Step 2: validate under SHARE UPDATE EXCLUSIVE (orders) / ROW SHARE (customers): non-blocking.
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_nn_chk;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey;

-- Step 3: real NOT NULL (no table scan: proven by validated CHECK), then drop helper CHECK.
DO $$
DECLARE
  deadline timestamptz := current_setting('migr.deadline')::timestamptz;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    PERFORM pg_stat_clear_snapshot();
    IF EXISTS (SELECT 1
                 FROM pg_locks l JOIN pg_stat_activity a ON a.pid = l.pid
                WHERE l.locktype = 'relation' AND l.relation = 'orders'::regclass
                  AND l.granted AND l.pid <> pg_backend_pid()
                  AND a.xact_start < clock_timestamp() - interval '250 milliseconds') THEN
      IF clock_timestamp() > deadline THEN
        RAISE EXCEPTION 'M2 step 3: could not acquire lock on orders before deadline';
      END IF;
      PERFORM pg_sleep(0.02);
      CONTINUE;
    END IF;
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      ALTER TABLE orders DROP CONSTRAINT orders_customer_id_nn_chk;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.05 + random() * 0.10);
    END;
  END LOOP;
END $$;
```

```sql
-- M3: UNIQUE constraint on orders(external_ref), online.
-- Strategy: build the unique index CONCURRENTLY (SHARE UPDATE EXCLUSIVE, never blocks app),
-- then attach it as a constraint (metadata only, brief ACCESS EXCLUSIVE retried with short
-- lock_timeout). lock_timeout must NOT be short during CIC: its internal waits for older
-- transactions/snapshots (e.g. the analytics job) are lock waits subject to lock_timeout.
SET lock_timeout = '30s';
SET maintenance_work_mem = '1GB';
DO $$ BEGIN
  PERFORM set_config('migr.deadline', (clock_timestamp() + interval '43 seconds')::text, false);
END $$;

CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders (external_ref);

DO $$
DECLARE
  deadline timestamptz := current_setting('migr.deadline')::timestamptz;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    PERFORM pg_stat_clear_snapshot();
    IF EXISTS (SELECT 1
                 FROM pg_locks l JOIN pg_stat_activity a ON a.pid = l.pid
                WHERE l.locktype = 'relation' AND l.relation = 'orders'::regclass
                  AND l.granted AND l.pid <> pg_backend_pid()
                  AND a.xact_start < clock_timestamp() - interval '250 milliseconds') THEN
      IF clock_timestamp() > deadline THEN
        RAISE EXCEPTION 'M3: could not acquire lock on orders before deadline';
      END IF;
      PERFORM pg_sleep(0.02);
      CONTINUE;
    END IF;
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.05 + random() * 0.10);
    END;
  END LOOP;
END $$;
```
