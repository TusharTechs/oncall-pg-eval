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

-- A volatile default in ADD COLUMN would rewrite the table under ACCESS EXCLUSIVE.
-- Instead: add a bare nullable column (metadata-only), then set the default (new rows only).
SELECT pg_temp.ddl_retry($q$ALTER TABLE public.orders ADD COLUMN public_id uuid$q$);
SELECT pg_temp.ddl_retry($q$ALTER TABLE public.orders ALTER COLUMN public_id SET DEFAULT gen_random_uuid()$q$);

-- Batched backfill, each batch its own short transaction.
SELECT format(
  'UPDATE public.orders SET public_id = gen_random_uuid() WHERE id > %s AND id <= %s AND public_id IS NULL',
  g, g + 10000)
FROM generate_series(0, (SELECT max(id) FROM public.orders), 10000) AS g
\gexec

-- Sweep for stragglers (e.g. rows inserted between the two ALTERs).
UPDATE public.orders SET public_id = gen_random_uuid() WHERE public_id IS NULL;

-- NOT NULL without a long ACCESS EXCLUSIVE scan.
SELECT pg_temp.ddl_retry($q$ALTER TABLE public.orders ADD CONSTRAINT orders_public_id_nn_chk CHECK (public_id IS NOT NULL) NOT VALID$q$);
ALTER TABLE public.orders VALIDATE CONSTRAINT orders_public_id_nn_chk;
SELECT pg_temp.ddl_retry($q$ALTER TABLE public.orders ALTER COLUMN public_id SET NOT NULL$q$);
SELECT pg_temp.ddl_retry($q$ALTER TABLE public.orders DROP CONSTRAINT orders_public_id_nn_chk$q$);
```
