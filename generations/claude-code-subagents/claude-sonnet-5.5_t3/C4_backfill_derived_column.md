```sql
CREATE FUNCTION pg_temp.ddl_retry(stmt text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
  i int;
BEGIN
  FOR i IN 1..200 LOOP
    BEGIN
      SET LOCAL lock_timeout = '100ms';
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      PERFORM pg_sleep(0.15);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock for: %', stmt;
END
$f$;

CREATE FUNCTION orders_set_amount_cents() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.amount_cents := (NEW.amount * 100)::bigint;
  RETURN NEW;
END
$$;

-- 1. Add nullable column (metadata only) and the trigger atomically, so every row
--    written from now on already carries the right value.
SELECT pg_temp.ddl_retry($q$
  ALTER TABLE orders ADD COLUMN amount_cents bigint;
  CREATE TRIGGER orders_amount_cents_trg
    BEFORE INSERT OR UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION orders_set_amount_cents()
$q$);

-- 2. Backfill existing rows in small committed batches (short row locks, bounded WAL bursts).
DO $$
DECLARE
  lo bigint := 0;
  mx bigint;
BEGIN
  SELECT max(id) INTO mx FROM orders;
  WHILE lo <= mx LOOP
    UPDATE orders
       SET amount_cents = (amount * 100)::bigint
     WHERE id > lo AND id <= lo + 10000
       AND amount_cents IS NULL;
    lo := lo + 10000;
    COMMIT;
  END LOOP;
END
$$;

-- 3. NOT NULL without a long ACCESS EXCLUSIVE scan: validated CHECK first.
SELECT pg_temp.ddl_retry($q$
  ALTER TABLE orders ADD CONSTRAINT orders_amount_cents_nn CHECK (amount_cents IS NOT NULL) NOT VALID
$q$);
ALTER TABLE orders VALIDATE CONSTRAINT orders_amount_cents_nn;
SELECT pg_temp.ddl_retry($q$ ALTER TABLE orders ALTER COLUMN amount_cents SET NOT NULL $q$);
SELECT pg_temp.ddl_retry($q$ ALTER TABLE orders DROP CONSTRAINT orders_amount_cents_nn $q$);
```
