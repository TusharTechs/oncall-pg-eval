-- M4: amount_cents bigint NOT NULL = (amount*100)::bigint for all rows, now and later.
-- Plan: add the column as NOT NULL with a constant fast default (metadata only, so
-- attnotnull is true from the start and no later ACCESS EXCLUSIVE step is needed),
-- atomically together with a BEFORE INSERT/UPDATE trigger that computes the value,
-- then backfill existing rows in small committed batches.

CREATE FUNCTION pg_temp.ddl_with_retry(VARIADIC stmts text[]) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  attempt int := 0;
  s text;
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      FOREACH s IN ARRAY stmts LOOP
        EXECUTE s;
      END LOOP;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      attempt := attempt + 1;
      IF attempt >= 600 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

CREATE FUNCTION public.orders_set_amount_cents() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.amount_cents := (NEW.amount * 100)::bigint;
  RETURN NEW;
END $$;

-- Column + trigger in ONE transaction, so no app row can be inserted with the
-- placeholder default after the column exists.
SELECT pg_temp.ddl_with_retry(
  'ALTER TABLE orders ADD COLUMN amount_cents bigint NOT NULL DEFAULT 0',
  'CREATE TRIGGER orders_set_amount_cents
     BEFORE INSERT OR UPDATE ON orders
     FOR EACH ROW EXECUTE FUNCTION public.orders_set_amount_cents()'
);

-- Batched backfill with a COMMIT per batch (short row-lock hold times).
CREATE PROCEDURE public.orders_backfill_amount_cents(batch_size bigint DEFAULT 10000)
LANGUAGE plpgsql AS $$
DECLARE
  lo bigint;
  hi bigint;
BEGIN
  -- every row with id > hi was inserted after the trigger existed
  SELECT min(id), max(id) INTO lo, hi FROM orders;
  COMMIT;
  IF lo IS NULL THEN
    RETURN;
  END IF;
  WHILE lo <= hi LOOP
    UPDATE orders
       SET amount_cents = (amount * 100)::bigint
     WHERE id >= lo AND id < lo + batch_size
       AND amount_cents IS DISTINCT FROM (amount * 100)::bigint;
    COMMIT;
    lo := lo + batch_size;
  END LOOP;
END $$;

SET lock_timeout = 0;
CALL public.orders_backfill_amount_cents(10000);

DROP PROCEDURE public.orders_backfill_amount_cents(bigint);
