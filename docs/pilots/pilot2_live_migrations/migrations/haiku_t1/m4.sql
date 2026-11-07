-- M4: orders.amount_cents bigint NOT NULL = (amount * 100)::bigint for all rows, forever
-- 1. Add the nullable column (metadata only).
-- 2. Install a BEFORE INSERT OR UPDATE trigger so every app insert/update from now on sets it.
--    The app does not know the column; the trigger fills it.
-- 3. Backfill existing rows in small committed batches, so row locks held by the backfill are
--    short and app updates on the same rows wait only milliseconds.
-- 4. Make it NOT NULL with the NOT VALID CHECK -> VALIDATE -> SET NOT NULL -> DROP CHECK pattern,
--    avoiding a 5M-row scan under ACCESS EXCLUSIVE.
SET lock_timeout = '100ms';

CREATE PROCEDURE mig_retry_ddl(stmt text)
LANGUAGE plpgsql AS $proc$
BEGIN
  FOR attempt IN 1..1000 LOOP
    BEGIN
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock for: %', stmt;
END
$proc$;

CALL mig_retry_ddl($q$ALTER TABLE orders ADD COLUMN amount_cents bigint$q$);

CREATE FUNCTION orders_set_amount_cents() RETURNS trigger
LANGUAGE plpgsql AS $f$
BEGIN
  NEW.amount_cents := (NEW.amount * 100)::bigint;
  RETURN NEW;
END
$f$;

CALL mig_retry_ddl($q$CREATE TRIGGER orders_set_amount_cents_trg BEFORE INSERT OR UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION orders_set_amount_cents()$q$);

-- Backfill: committed batches of 20000 rows in id order. lock_timeout is off here because the
-- backfill only waits on short row locks held by application transactions.
CREATE PROCEDURE mig_backfill_amount_cents()
LANGUAGE plpgsql AS $p$
DECLARE
  last_id bigint := 0;
  batch_end bigint;
BEGIN
  LOOP
    SELECT max(id) INTO batch_end
      FROM (SELECT id FROM orders WHERE id > last_id ORDER BY id LIMIT 20000) s;
    EXIT WHEN batch_end IS NULL;

    UPDATE orders
       SET amount_cents = (amount * 100)::bigint
     WHERE id > last_id AND id <= batch_end AND amount_cents IS NULL;

    last_id := batch_end;
    COMMIT;
  END LOOP;
END
$p$;

SET lock_timeout = 0;
CALL mig_backfill_amount_cents();
DROP PROCEDURE mig_backfill_amount_cents();

-- Rows inserted after the trigger existed are already set by the trigger, so the backfill
-- covers only pre-existing rows and nothing is left NULL.
SET lock_timeout = '100ms';
CALL mig_retry_ddl($q$ALTER TABLE orders ADD CONSTRAINT orders_amount_cents_nn CHECK (amount_cents IS NOT NULL) NOT VALID$q$);
CALL mig_retry_ddl($q$ALTER TABLE orders VALIDATE CONSTRAINT orders_amount_cents_nn$q$);
CALL mig_retry_ddl($q$ALTER TABLE orders ALTER COLUMN amount_cents SET NOT NULL$q$);
CALL mig_retry_ddl($q$ALTER TABLE orders DROP CONSTRAINT orders_amount_cents_nn$q$);

DROP PROCEDURE mig_retry_ddl(text);
