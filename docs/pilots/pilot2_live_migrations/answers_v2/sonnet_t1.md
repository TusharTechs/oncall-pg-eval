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
      IF i > 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;
RESET lock_timeout;
```

```sql
-- M2
SET lock_timeout = '50ms';

-- helper CHECK (brief ACCESS EXCLUSIVE, retried) so SET NOT NULL can skip the table scan
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_cust_nn_chk CHECK (customer_id IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;

-- FK added NOT VALID (no scan), retried on lock timeout
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_customer_fk
        FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;

RESET lock_timeout;

-- long scans, only SHARE UPDATE EXCLUSIVE (do not block app writes)
ALTER TABLE orders VALIDATE CONSTRAINT orders_cust_nn_chk;
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_fk;

SET lock_timeout = '50ms';

-- SET NOT NULL uses the validated CHECK, so no scan under ACCESS EXCLUSIVE
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;

DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders DROP CONSTRAINT orders_cust_nn_chk;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;

RESET lock_timeout;
```

```sql
-- M3
-- CONCURRENTLY: does not block app writes (it waits for the open analytics txn, which is fine)
SET lock_timeout = 0;
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_uq_idx ON orders (external_ref);

SET lock_timeout = '50ms';
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_external_ref_uq
        UNIQUE USING INDEX orders_external_ref_uq_idx;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;
RESET lock_timeout;
```

```sql
-- M4
SET lock_timeout = '50ms';

-- 1. nullable column (metadata only), retried on lock timeout
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN amount_cents bigint;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;

-- 2. trigger keeps every new/updated row correct, so the unchanged app works
CREATE OR REPLACE FUNCTION orders_set_amount_cents() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.amount_cents := (NEW.amount * 100)::bigint;
  RETURN NEW;
END $$;

DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      CREATE TRIGGER orders_amount_cents_trg
        BEFORE INSERT OR UPDATE ON orders
        FOR EACH ROW EXECUTE FUNCTION orders_set_amount_cents();
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;

RESET lock_timeout;

-- 3. batched backfill, one small transaction per batch
SET synchronous_commit = off;
DO $$
DECLARE
  lo bigint := 0;
  hi bigint;
  maxid bigint;
  step constant bigint := 5000;
BEGIN
  SELECT max(id) INTO maxid FROM orders;
  WHILE lo < maxid LOOP
    hi := lo + step;
    UPDATE orders
       SET amount_cents = (amount * 100)::bigint
     WHERE id > lo AND id <= hi AND amount_cents IS NULL;
    COMMIT;
    lo := hi;
  END LOOP;
END $$;

-- 4. NOT NULL without a long ACCESS EXCLUSIVE scan
ALTER TABLE orders ADD CONSTRAINT orders_amount_cents_nn_chk CHECK (amount_cents IS NOT NULL) NOT VALID;
