```sql
-- M1
SET lock_timeout = '50ms';
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU';
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;
```

```sql
-- M2
SET lock_timeout = '50ms';

-- 1. FK as NOT VALID (brief lock, retried)
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_customer_id_fkey
        FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

-- 2. Validate FK (does not block writes)
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey;

-- 3. CHECK (customer_id IS NOT NULL) as NOT VALID (brief lock, retried)
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_customer_id_nn
        CHECK (customer_id IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_nn;

-- 4. SET NOT NULL (skips scan thanks to validated CHECK; retried)
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

-- 5. Drop helper constraint (retried)
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders DROP CONSTRAINT orders_customer_id_nn;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;
```

```sql
-- M3
-- CIC must wait for older transactions (the analytics txn); lock_timeout must not apply to that wait.
SET lock_timeout = 0;
SET max_parallel_maintenance_workers = 4;
SET maintenance_work_mem = '512MB';
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_uq ON orders(external_ref);

SET lock_timeout = '50ms';
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key
        UNIQUE USING INDEX orders_external_ref_uq;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;
```

```sql
-- M4
SET lock_timeout = '50ms';

CREATE OR REPLACE FUNCTION orders_set_amount_cents() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.amount_cents := (NEW.amount * 100)::bigint;
  RETURN NEW;
END $$;

-- 1. Add column and trigger atomically so no row can be missed (retried on lock timeout)
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN amount_cents bigint;
      CREATE TRIGGER orders_amount_cents_trg
        BEFORE INSERT OR UPDATE ON orders
        FOR EACH ROW EXECUTE FUNCTION orders_set_amount_cents();
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

-- 2. Batched backfill, committing per batch; row-lock waits must not hit lock_timeout
SET lock_timeout = 0;
DO $$
DECLARE
  lo bigint;
  hi bigint;
BEGIN
  SELECT min(id), max(id) INTO lo, hi FROM orders;
  WHILE lo <= hi LOOP
    UPDATE orders
       SET amount_cents = (amount * 100)::bigint
     WHERE id >= lo AND id < lo + 5000
       AND amount_cents IS NULL;
    COMMIT;
    lo := lo + 5000;
  END LOOP;
END $$;

-- 3. NOT NULL via validated CHECK
SET lock_timeout = '50ms';
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_amount_cents_nn
        CHECK (amount_cents IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

ALTER TABLE orders VALIDATE CONSTRAINT orders_amount_cents_nn;

DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN amount_cents SET NOT NULL;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders DROP CONSTRAINT orders_amount_cents_nn;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;
```
