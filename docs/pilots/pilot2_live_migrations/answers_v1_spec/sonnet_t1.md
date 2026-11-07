```sql
-- M1
CREATE FUNCTION pg_temp.retry_ddl(stmt text, max_tries int DEFAULT 60) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE i int;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  FOR i IN 1..max_tries LOOP
    BEGIN
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available OR deadlock_detected THEN
      PERFORM pg_sleep(0.3);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock for: %', stmt;
END $$;

-- Constant default: metadata-only in PG11+, no table rewrite.
SELECT pg_temp.retry_ddl($q$ALTER TABLE public.orders ADD COLUMN region text NOT NULL DEFAULT 'EU'$q$);
```

```sql
-- M2
CREATE FUNCTION pg_temp.retry_ddl(stmt text, max_tries int DEFAULT 60) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE i int;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  FOR i IN 1..max_tries LOOP
    BEGIN
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available OR deadlock_detected THEN
      PERFORM pg_sleep(0.3);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock for: %', stmt;
END $$;

-- NOT NULL via a validated CHECK so SET NOT NULL skips the full scan.
SELECT pg_temp.retry_ddl($q$ALTER TABLE public.orders ADD CONSTRAINT orders_customer_id_nn CHECK (customer_id IS NOT NULL) NOT VALID$q$);
-- Foreign key added NOT VALID (brief lock, no scan), validated later without blocking writes.
SELECT pg_temp.retry_ddl($q$ALTER TABLE public.orders ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) NOT VALID$q$);

SET lock_timeout = 0;
ALTER TABLE public.orders VALIDATE CONSTRAINT orders_customer_id_nn;
ALTER TABLE public.orders VALIDATE CONSTRAINT orders_customer_id_fkey;

SELECT pg_temp.retry_ddl($q$ALTER TABLE public.orders ALTER COLUMN customer_id SET NOT NULL$q$);
SELECT pg_temp.retry_ddl($q$ALTER TABLE public.orders DROP CONSTRAINT orders_customer_id_nn$q$);
```

```sql
-- M3
CREATE FUNCTION pg_temp.retry_ddl(stmt text, max_tries int DEFAULT 60) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE i int;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  FOR i IN 1..max_tries LOOP
    BEGIN
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available OR deadlock_detected THEN
      PERFORM pg_sleep(0.3);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock for: %', stmt;
END $$;

SET maintenance_work_mem = '512MB';
SET lock_timeout = 0;
-- Build the unique index without blocking writes (must be top-level, not in a transaction).
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON public.orders (external_ref);

-- Attach it as a constraint; brief ACCESS EXCLUSIVE lock with bounded wait and retry.
SELECT pg_temp.retry_ddl($q$ALTER TABLE public.orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key$q$);
```
