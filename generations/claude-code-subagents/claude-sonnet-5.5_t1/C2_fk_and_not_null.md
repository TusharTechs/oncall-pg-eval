```sql
CREATE FUNCTION pg_temp.ddl_retry(stmt text, max_tries int DEFAULT 400)
RETURNS void LANGUAGE plpgsql
SET lock_timeout = '30ms'
AS $$
BEGIN
  FOR i IN 1..max_tries LOOP
    BEGIN
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock for: %', stmt;
END
$$;

-- 1. Add constraints without scanning (brief lock only).
SELECT pg_temp.ddl_retry($q$ALTER TABLE public.orders ADD CONSTRAINT orders_customer_id_nn_chk CHECK (customer_id IS NOT NULL) NOT VALID$q$);
SELECT pg_temp.ddl_retry($q$ALTER TABLE public.orders ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) NOT VALID$q$);

-- 2. Validate with weak locks (does not block app reads/writes).
ALTER TABLE public.orders VALIDATE CONSTRAINT orders_customer_id_nn_chk;
ALTER TABLE public.orders VALIDATE CONSTRAINT orders_customer_id_fkey;

-- 3. SET NOT NULL skips the scan because a validated CHECK proves it (PG12+).
SELECT pg_temp.ddl_retry($q$ALTER TABLE public.orders ALTER COLUMN customer_id SET NOT NULL$q$);

-- 4. Drop the helper constraint.
SELECT pg_temp.ddl_retry($q$ALTER TABLE public.orders DROP CONSTRAINT orders_customer_id_nn_chk$q$);
```
