```sql
-- H1: add orders.public_id uuid NOT NULL DEFAULT gen_random_uuid() online.
-- A volatile default in ADD COLUMN would rewrite 5M rows under ACCESS EXCLUSIVE,
-- so: add nullable column + set default (metadata only), backfill in small
-- committed batches, prove NOT NULL via a validated CHECK, then SET NOT NULL.
-- Every ACCESS EXCLUSIVE step uses a short lock_timeout with retries so we never
-- queue the app behind the long-running analytics transaction.

SET statement_timeout = 0;

-- Step 1: add column (no default => no rewrite) and set the volatile default for new rows.
SET lock_timeout = '100ms';
DO $$
DECLARE n int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS public_id uuid;
      ALTER TABLE public.orders ALTER COLUMN public_id SET DEFAULT gen_random_uuid();
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      n := n + 1;
      IF n >= 200 THEN RAISE; END IF;
      PERFORM pg_sleep(0.2);
    END;
  END LOOP;
END $$;

-- Step 2: backfill existing rows in small batches, committing each batch
-- (keeps row locks short so app UPDATEs never wait long).
SET lock_timeout = 0;
DO $$
DECLARE
  v_max  bigint;
  v_lo   bigint;
  v_step constant bigint := 10000;
BEGIN
  SELECT coalesce(max(id), 0) INTO v_max FROM public.orders;
  SELECT coalesce(min(id), 1) - 1 INTO v_lo FROM public.orders;
  WHILE v_lo < v_max LOOP
    UPDATE public.orders
       SET public_id = gen_random_uuid()
     WHERE id > v_lo AND id <= v_lo + v_step
       AND public_id IS NULL;
    v_lo := v_lo + v_step;
    COMMIT;
  END LOOP;
END $$;

-- Safety pass (should touch 0 rows; takes no row locks if nothing matches).
UPDATE public.orders SET public_id = gen_random_uuid() WHERE public_id IS NULL;

-- Step 3: NOT VALID check constraint (brief ACCESS EXCLUSIVE, retried).
SET lock_timeout = '100ms';
DO $$
DECLARE n int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE public.orders
        ADD CONSTRAINT orders_public_id_not_null CHECK (public_id IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      n := n + 1;
      IF n >= 200 THEN RAISE; END IF;
      PERFORM pg_sleep(0.2);
    END;
  END LOOP;
END $$;

-- Step 4: validate (SHARE UPDATE EXCLUSIVE: does not block app reads/writes).
SET lock_timeout = 0;
ALTER TABLE public.orders VALIDATE CONSTRAINT orders_public_id_not_null;

-- Step 5: SET NOT NULL (no scan: proven by the valid CHECK), then drop the helper CHECK.
SET lock_timeout = '100ms';
DO $$
DECLARE n int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE public.orders ALTER COLUMN public_id SET NOT NULL;
      ALTER TABLE public.orders DROP CONSTRAINT orders_public_id_not_null;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      n := n + 1;
      IF n >= 200 THEN RAISE; END IF;
      PERFORM pg_sleep(0.2);
    END;
  END LOOP;
END $$;

RESET lock_timeout;
```
