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

-- 1. Nullable column, no default: metadata-only.
SELECT pg_temp.ddl_retry($q$ALTER TABLE public.orders ADD COLUMN amount_cents bigint$q$);

-- 2. Trigger keeps new/updated rows correct. The WHEN clause makes it a no-op
--    (no plpgsql call) for rows that are already correct, e.g. during backfill.
CREATE FUNCTION public.orders_set_amount_cents() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.amount_cents := (NEW.amount * 100)::bigint;
  RETURN NEW;
END
$$;

SELECT pg_temp.ddl_retry($q$CREATE TRIGGER orders_amount_cents_trg
  BEFORE INSERT OR UPDATE ON public.orders
  FOR EACH ROW
  WHEN (NEW.amount_cents IS DISTINCT FROM (NEW.amount * 100)::bigint)
  EXECUTE FUNCTION public.orders_set_amount_cents()$q$);

-- 3. Batched backfill: each UPDATE is its own short autocommit transaction.
SELECT format(
  'UPDATE public.orders SET amount_cents = (amount * 100)::bigint WHERE id > %s AND id <= %s AND amount_cents IS NULL',
  g, g + 10000)
FROM generate_series(0, (SELECT max(id) FROM public.orders), 10000) AS g
\gexec

-- Safety sweep for any straggler.
UPDATE public.orders SET amount_cents = (amount * 100)::bigint WHERE amount_cents IS NULL;

-- 4. NOT NULL without a long ACCESS EXCLUSIVE scan.
SELECT pg_temp.ddl_retry($q$ALTER TABLE public.orders ADD CONSTRAINT orders_amount_cents_nn_chk CHECK (amount_cents IS NOT NULL) NOT VALID$q$);
ALTER TABLE public.orders VALIDATE CONSTRAINT orders_amount_cents_nn_chk;
SELECT pg_temp.ddl_retry($q$ALTER TABLE public.orders ALTER COLUMN amount_cents SET NOT NULL$q$);
SELECT pg_temp.ddl_retry($q$ALTER TABLE public.orders DROP CONSTRAINT orders_amount_cents_nn_chk$q$);
```
