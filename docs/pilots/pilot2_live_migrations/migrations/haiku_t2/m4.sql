-- M4: orders.amount_cents bigint NOT NULL = (amount * 100)::bigint
SET lock_timeout = '100ms';

CREATE FUNCTION pg_temp.retry_ddl(stmt text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '30 seconds';
BEGIN
  LOOP
    BEGIN
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() >= deadline THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

-- nullable column without default: metadata-only change
SELECT pg_temp.retry_ddl('ALTER TABLE orders ADD COLUMN amount_cents bigint');

CREATE FUNCTION orders_set_amount_cents() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.amount_cents := (NEW.amount * 100)::bigint;
  RETURN NEW;
END
$$;

-- trigger first: every row written from now on is covered
SELECT pg_temp.retry_ddl('CREATE TRIGGER orders_amount_cents_trg BEFORE INSERT OR UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION orders_set_amount_cents()');

-- backfill existing rows in 5000-row keyset batches, committing each batch
SET lock_timeout = 0;
DO $$
DECLARE
  lo bigint := 0;
  hi bigint;
  maxid bigint;
BEGIN
  SELECT max(id) INTO maxid FROM orders;
  WHILE lo < maxid LOOP
    SELECT max(id) INTO hi
      FROM (SELECT id FROM orders WHERE id > lo ORDER BY id LIMIT 5000) s;
    UPDATE orders
       SET amount_cents = (amount * 100)::bigint
     WHERE id > lo AND id <= hi
       AND amount_cents IS DISTINCT FROM (amount * 100)::bigint;
    COMMIT;
    lo := hi;
  END LOOP;
END
$$;
SET lock_timeout = '100ms';

-- NOT NULL via validated CHECK, so SET NOT NULL skips the table scan
SELECT pg_temp.retry_ddl('ALTER TABLE orders ADD CONSTRAINT orders_amount_cents_not_null CHECK (amount_cents IS NOT NULL) NOT VALID');
SELECT pg_temp.retry_ddl('ALTER TABLE orders VALIDATE CONSTRAINT orders_amount_cents_not_null');
SELECT pg_temp.retry_ddl('ALTER TABLE orders ALTER COLUMN amount_cents SET NOT NULL');
SELECT pg_temp.retry_ddl('ALTER TABLE orders DROP CONSTRAINT orders_amount_cents_not_null');
