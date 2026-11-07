```sql
-- M1: add region text NOT NULL DEFAULT 'EU' (PG11+ fast default: metadata-only, no rewrite).
-- The only risk is the ACCESS EXCLUSIVE lock queueing behind the open analytics
-- transaction and stalling the app, so acquire it with a short lock_timeout and retry.

CREATE FUNCTION pg_temp.ddl_with_retry(VARIADIC stmts text[]) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  attempt int := 0;
  s text;
BEGIN
  -- transaction-local: only affects this call
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      FOREACH s IN ARRAY stmts LOOP
        EXECUTE s;
      END LOOP;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      attempt := attempt + 1;
      IF attempt >= 300 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

SELECT pg_temp.ddl_with_retry(
  $q$ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU'$q$
);
```

```sql
-- M2: customer_id NOT NULL + validated FK to customers(id), without long blocking locks.

CREATE FUNCTION pg_temp.ddl_with_retry(VARIADIC stmts text[]) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  attempt int := 0;
  s text;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      FOREACH s IN ARRAY stmts LOOP
        EXECUTE s;
      END LOOP;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      attempt := attempt + 1;
      IF attempt >= 300 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

-- 1) FK as NOT VALID: brief SHARE ROW EXCLUSIVE on orders/customers (does not conflict
--    with the analytics ACCESS SHARE, only briefly with app writers).
SELECT pg_temp.ddl_with_retry(
  'ALTER TABLE orders ADD CONSTRAINT orders_customer_id_fkey
     FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID'
);

-- 2) Validate FK: SHARE UPDATE EXCLUSIVE only, does not block app traffic.
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey;

-- 3) Helper CHECK as NOT VALID: brief ACCESS EXCLUSIVE (waits for analytics via retries).
SELECT pg_temp.ddl_with_retry(
  'ALTER TABLE orders ADD CONSTRAINT orders_customer_id_not_null
     CHECK (customer_id IS NOT NULL) NOT VALID'
);

-- 4) Validate CHECK: SHARE UPDATE EXCLUSIVE, full scan without blocking app.
ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_not_null;

-- 5) SET NOT NULL uses the validated CHECK to skip the table scan (PG12+),
--    then drop the now-redundant helper in the same short transaction.
SELECT pg_temp.ddl_with_retry(
  'ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL',
  'ALTER TABLE orders DROP CONSTRAINT orders_customer_id_not_null'
);
```

```sql
-- M3: UNIQUE constraint on orders(external_ref) backed by a concurrently built index.

CREATE FUNCTION pg_temp.ddl_with_retry(VARIADIC stmts text[]) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  attempt int := 0;
  s text;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      FOREACH s IN ARRAY stmts LOOP
        EXECUTE s;
      END LOOP;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      attempt := attempt + 1;
      IF attempt >= 300 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

SET maintenance_work_mem = '512MB';
-- session lock_timeout stays 0 here: CIC must be allowed to wait for the analytics
-- transaction's snapshot (lock_timeout would otherwise abort its virtual-xid waits).
SET lock_timeout = 0;

DROP INDEX CONCURRENTLY IF EXISTS orders_external_ref_key;

-- SHARE UPDATE EXCLUSIVE only: app reads/writes continue during the build.
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders (external_ref);

-- Attach as a constraint: metadata-only, brief ACCESS EXCLUSIVE with retry.
SELECT pg_temp.ddl_with_retry(
  'ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key'
);
```

```sql
-- M4: amount_cents bigint NOT NULL = (amount*100)::bigint for all rows, now and later.
-- Plan: add the column as NOT NULL with a constant fast default (metadata only, so
-- attnotnull is true from the start and no later ACCESS EXCLUSIVE step is needed),
-- atomically together with a BEFORE INSERT/UPDATE trigger that computes the value,
-- then backfill existing rows in small committed batches.

CREATE FUNCTION pg_temp.ddl_with_retry(VARIADIC stmts text[]) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  attempt int := 0;
  s text;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      FOREACH s IN ARRAY stmts LOOP
        EXECUTE s;
      END LOOP;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      attempt := attempt + 1;
      IF attempt >= 600 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

CREATE FUNCTION public.orders_set_amount_cents() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.amount_cents := (NEW.amount * 100)::bigint;
  RETURN NEW;
END $$;

-- Column + trigger in ONE transaction, so no app row can be inserted with the
-- placeholder default after the column exists.
SELECT pg_temp.ddl_with_retry(
  'ALTER TABLE orders ADD COLUMN amount_cents bigint NOT NULL DEFAULT 0',
  'CREATE TRIGGER orders_set_amount_cents
     BEFORE INSERT OR UPDATE ON orders
     FOR EACH ROW EXECUTE FUNCTION public.orders_set_amount_cents()'
);

-- Batched backfill with a COMMIT per batch (short row-lock hold times).
CREATE PROCEDURE public.orders_backfill_amount_cents(batch_size bigint DEFAULT 10000)
LANGUAGE plpgsql AS $$
DECLARE
  lo bigint;
  hi bigint;
BEGIN
  -- every row with id > hi was inserted after the trigger existed
  SELECT min(id), max(id) INTO lo, hi FROM orders;
  COMMIT;
  IF lo IS NULL THEN
    RETURN;
  END IF;
  WHILE lo <= hi LOOP
    UPDATE orders
       SET amount_cents = (amount * 100)::bigint
     WHERE id >= lo AND id < lo + batch_size
       AND amount_cents IS DISTINCT FROM (amount * 100)::bigint;
    COMMIT;
    lo := lo + batch_size;
  END LOOP;
END $$;

SET lock_timeout = 0;
CALL public.orders_backfill_amount_cents(10000);

DROP PROCEDURE public.orders_backfill_amount_cents(bigint);
```
