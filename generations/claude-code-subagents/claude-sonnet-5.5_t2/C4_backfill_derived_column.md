```sql
CREATE OR REPLACE FUNCTION orders_set_amount_cents() RETURNS trigger
LANGUAGE plpgsql AS $f$
BEGIN
  NEW.amount_cents := (NEW.amount * 100)::bigint;
  RETURN NEW;
END
$f$;

-- Step 1: add column, NOT VALID helper CHECK and trigger together (brief lock, retry).
SET lock_timeout = '50ms';

DO $$
DECLARE
  i int;
BEGIN
  FOR i IN 1..150 LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN amount_cents bigint;
      ALTER TABLE orders ADD CONSTRAINT orders_amount_cents_nn CHECK (amount_cents IS NOT NULL) NOT VALID;
      CREATE TRIGGER orders_amount_cents_trg
        BEFORE INSERT OR UPDATE ON orders
        FOR EACH ROW EXECUTE FUNCTION orders_set_amount_cents();
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

-- Step 2: batched backfill, each batch its own short autocommit transaction.
SELECT format(
  'UPDATE orders SET amount_cents = (amount * 100)::bigint WHERE id > %s AND id <= %s AND amount_cents IS NULL',
  g, g + 5000)
FROM generate_series(0, (SELECT max(id) FROM orders), 5000) AS g
\gexec

-- Step 3: validate (does not block writes), then SET NOT NULL without a scan, drop helper.
ALTER TABLE orders VALIDATE CONSTRAINT orders_amount_cents_nn;

SET lock_timeout = '50ms';

DO $$
DECLARE
  i int;
BEGIN
  FOR i IN 1..150 LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN amount_cents SET NOT NULL;
      ALTER TABLE orders DROP CONSTRAINT orders_amount_cents_nn;
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
