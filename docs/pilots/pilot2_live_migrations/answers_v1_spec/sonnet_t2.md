```sql
-- M1: constant default is metadata-only in PG11+; only the lock acquisition needs care.
DO $$
DECLARE i int := 0;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU';
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 150 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;
```

```sql
-- M2
-- 1) FK as NOT VALID (brief lock, no scan), with retry on lock timeout.
DO $$
DECLARE i int := 0;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_customer_id_fkey
        FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID;
      ALTER TABLE orders ADD CONSTRAINT orders_customer_id_nn
        CHECK (customer_id IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 150 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

-- 2) Validate without blocking writes (SHARE UPDATE EXCLUSIVE).
SET lock_timeout = 0;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_nn;

-- 3) SET NOT NULL skips the table scan thanks to the validated CHECK.
DO $$
DECLARE i int := 0;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      ALTER TABLE orders DROP CONSTRAINT orders_customer_id_nn;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 150 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;
```

```sql
-- M3
-- 1) Build the unique index without blocking writes (waits out analytics txns; fine within budget).
SET lock_timeout = 0;
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders (external_ref);

-- 2) Attach as constraint; brief ACCESS EXCLUSIVE lock, retried on lock timeout.
DO $$
DECLARE i int := 0;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key
        UNIQUE USING INDEX orders_external_ref_key;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 150 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;
```
