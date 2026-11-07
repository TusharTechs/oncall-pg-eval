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
