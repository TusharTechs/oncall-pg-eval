```sql
-- A volatile default on ADD COLUMN would rewrite the table under ACCESS EXCLUSIVE.
-- Instead: add a bare nullable column, then set the default (both metadata-only), then backfill in batches.
SET lock_timeout = '50ms';

DO $$
DECLARE
  i int;
BEGIN
  FOR i IN 1..150 LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN public_id uuid;
      ALTER TABLE orders ALTER COLUMN public_id SET DEFAULT gen_random_uuid();
      ALTER TABLE orders ADD CONSTRAINT orders_public_id_nn CHECK (public_id IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF i = 150 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;

RESET lock_timeout;

-- Batched backfill; each batch is its own short autocommit transaction.
SELECT format(
  'UPDATE orders SET public_id = gen_random_uuid() WHERE id > %s AND id <= %s AND public_id IS NULL',
  g, g + 5000)
FROM generate_series(0, (SELECT max(id) FROM orders), 5000) AS g
\gexec

-- Validate without blocking writes, then NOT NULL (no scan thanks to the validated CHECK), drop helper.
ALTER TABLE orders VALIDATE CONSTRAINT orders_public_id_nn;

SET lock_timeout = '50ms';

DO $$
DECLARE
  i int;
BEGIN
  FOR i IN 1..150 LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN public_id SET NOT NULL;
      ALTER TABLE orders DROP CONSTRAINT orders_public_id_nn;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF i = 150 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;

RESET lock_timeout;
```
