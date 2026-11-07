```sql
-- M1: add orders.region text NOT NULL DEFAULT 'EU'
SET lock_timeout = 0;
SET statement_timeout = 0;

-- Helper: first take SHARE UPDATE EXCLUSIVE (does not conflict with the app or the analytics reader,
-- but makes a non-wraparound autovacuum get cancelled), then try the ACCESS EXCLUSIVE DDL with a short
-- lock_timeout so the app is never queued behind us for more than ~100 ms; retry until the
-- long-running analytics transaction has gone away.
CREATE FUNCTION pg_temp.run_ddl(stmts text[]) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  attempt int := 0;
  s text;
BEGIN
  PERFORM set_config('lock_timeout', '0', true);
  LOCK TABLE public.orders IN SHARE UPDATE EXCLUSIVE MODE;
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    attempt := attempt + 1;
    BEGIN
      FOREACH s IN ARRAY stmts LOOP
        EXECUTE s;
      END LOOP;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF attempt >= 300 THEN
        RAISE;
      END IF;
    END;
    PERFORM pg_sleep(0.1 + random() * 0.05);
  END LOOP;
END
$$;

-- Constant default => metadata-only (missing value), no rewrite and no NOT NULL scan.
SELECT pg_temp.run_ddl(ARRAY[
  $q$ALTER TABLE public.orders ADD COLUMN region text NOT NULL DEFAULT 'EU'$q$
]);
```

```sql
-- M2: orders.customer_id NOT NULL + validated FK to customers(id)
SET lock_timeout = 0;
SET statement_timeout = 0;

CREATE FUNCTION pg_temp.run_ddl(stmts text[]) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  attempt int := 0;
  s text;
BEGIN
  PERFORM set_config('lock_timeout', '0', true);
  LOCK TABLE public.orders IN SHARE UPDATE EXCLUSIVE MODE;
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    attempt := attempt + 1;
    BEGIN
      FOREACH s IN ARRAY stmts LOOP
        EXECUTE s;
      END LOOP;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF attempt >= 300 THEN
        RAISE;
      END IF;
    END;
    PERFORM pg_sleep(0.1 + random() * 0.05);
  END LOOP;
END
$$;

-- 1. Add both constraints NOT VALID (brief lock, no scan; enforced for new/updated rows from now on).
SELECT pg_temp.run_ddl(ARRAY[
  'ALTER TABLE public.orders ADD CONSTRAINT orders_customer_id_not_null CHECK (customer_id IS NOT NULL) NOT VALID',
  'ALTER TABLE public.orders ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) NOT VALID'
]);

-- 2. Validate (SHARE UPDATE EXCLUSIVE on orders, ROW SHARE on customers: does not block the app).
ALTER TABLE public.orders VALIDATE CONSTRAINT orders_customer_id_not_null;
ALTER TABLE public.orders VALIDATE CONSTRAINT orders_customer_id_fkey;

-- 3. SET NOT NULL: the validated CHECK proves no NULLs, so no table scan under ACCESS EXCLUSIVE.
--    (The helper CHECK constraint is intentionally left in place.)
SELECT pg_temp.run_ddl(ARRAY[
  'ALTER TABLE public.orders ALTER COLUMN customer_id SET NOT NULL'
]);
```

```sql
-- M3: UNIQUE constraint on orders(external_ref)
SET lock_timeout = 0;
SET statement_timeout = 0;
SET maintenance_work_mem = '1GB';

CREATE FUNCTION pg_temp.run_ddl(stmts text[]) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  attempt int := 0;
  s text;
BEGIN
  PERFORM set_config('lock_timeout', '0', true);
  LOCK TABLE public.orders IN SHARE UPDATE EXCLUSIVE MODE;
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    attempt := attempt + 1;
    BEGIN
      FOREACH s IN ARRAY stmts LOOP
        EXECUTE s;
      END LOOP;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF attempt >= 300 THEN
        RAISE;
      END IF;
    END;
    PERFORM pg_sleep(0.1 + random() * 0.05);
  END LOOP;
END
$$;

-- 1. Build the unique index without blocking writes (lock_timeout must be 0 here: CIC's waits
--    for older transactions/snapshots are lock waits).
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON public.orders (external_ref);

-- 2. Attach it as a constraint (brief ACCESS EXCLUSIVE, no scan).
SELECT pg_temp.run_ddl(ARRAY[
  'ALTER TABLE public.orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key'
]);
```

```sql
-- M4: orders.amount_cents bigint NOT NULL, always = (amount * 100)::bigint
SET lock_timeout = 0;
SET statement_timeout = 0;
SET plan_cache_mode = force_custom_plan;

CREATE FUNCTION pg_temp.run_ddl(stmts text[]) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  attempt int := 0;
  s text;
BEGIN
  PERFORM set_config('lock_timeout', '0', true);
  LOCK TABLE public.orders IN SHARE UPDATE EXCLUSIVE MODE;
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    attempt := attempt + 1;
    BEGIN
      FOREACH s IN ARRAY stmts LOOP
        EXECUTE s;
      END LOOP;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF attempt >= 400 THEN
        RAISE;
      END IF;
    END;
    PERFORM pg_sleep(0.1 + random() * 0.05);
  END LOOP;
END
$$;

-- Permanent trigger function keeping amount_cents in sync for all inserts/updates.
CREATE FUNCTION public.orders_set_amount_cents() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.amount_cents := (NEW.amount * 100)::bigint;
  RETURN NEW;
END
$$;

-- 1. Add nullable column (metadata only), a NOT VALID NOT NULL check, and the trigger, atomically.
SELECT pg_temp.run_ddl(ARRAY[
  'ALTER TABLE public.orders ADD COLUMN amount_cents bigint',
  'ALTER TABLE public.orders ADD CONSTRAINT orders_amount_cents_not_null CHECK (amount_cents IS NOT NULL) NOT VALID',
  'CREATE TRIGGER orders_amount_cents_trg BEFORE INSERT OR UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.orders_set_amount_cents()'
]);

-- 2. Backfill existing rows in small committed batches (short row-lock hold times).
DO $$
DECLARE
  last_id bigint;
  max_id  bigint;
  hi      bigint;
BEGIN
  SELECT min(id) - 1, max(id) INTO last_id, max_id FROM public.orders;
  IF max_id IS NULL THEN
    RETURN;
  END IF;
  LOOP
    SELECT max(id) INTO hi
      FROM (SELECT id FROM public.orders
             WHERE id > last_id AND id <= max_id
             ORDER BY id
             LIMIT 5000) s;
    EXIT WHEN hi IS NULL;
    UPDATE public.orders
       SET amount_cents = (amount * 100)::bigint
     WHERE id > last_id AND id <= hi
       AND amount_cents IS NULL;
    COMMIT;
    last_id := hi;
  END LOOP;
END
$$;

-- Safety net (normally matches nothing; only locks rows it actually updates).
UPDATE public.orders SET amount_cents = (amount * 100)::bigint WHERE amount_cents IS NULL;

-- 3. Validate the check (SHARE UPDATE EXCLUSIVE: does not block the app).
ALTER TABLE public.orders VALIDATE CONSTRAINT orders_amount_cents_not_null;

-- 4. SET NOT NULL: proven by the validated CHECK, so no scan under ACCESS EXCLUSIVE.
--    (Helper CHECK constraint and the trigger stay in place.)
SELECT pg_temp.run_ddl(ARRAY[
  'ALTER TABLE public.orders ALTER COLUMN amount_cents SET NOT NULL'
]);
```
