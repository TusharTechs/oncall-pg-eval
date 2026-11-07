```sql
-- M1: orders.region text NOT NULL DEFAULT 'EU'
-- PG11+ stores a constant non-volatile default as metadata only (no rewrite, no scan).
-- The only real cost is the ACCESS EXCLUSIVE lock, taken with a short lock_timeout and retried
-- so application transactions are never queued behind it for long.
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

CALL mig_retry_ddl($q$ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU'$q$);

DROP PROCEDURE mig_retry_ddl(text);
```

```sql
-- M2: orders.customer_id NOT NULL + validated FK to customers(id)
-- SET NOT NULL alone would scan 5M rows under ACCESS EXCLUSIVE and stall the app.
-- Instead: NOT VALID CHECK -> VALIDATE (SHARE UPDATE EXCLUSIVE, does not block DML) ->
-- SET NOT NULL (PG12+ skips the scan because a validated CHECK proves it) -> drop helper CHECK.
-- The FK is added NOT VALID (catalog-only) and validated separately, without blocking DML.
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

CALL mig_retry_ddl($q$ALTER TABLE orders ADD CONSTRAINT orders_customer_id_nn CHECK (customer_id IS NOT NULL) NOT VALID$q$);
CALL mig_retry_ddl($q$ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_nn$q$);
CALL mig_retry_ddl($q$ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL$q$);
CALL mig_retry_ddl($q$ALTER TABLE orders DROP CONSTRAINT orders_customer_id_nn$q$);

CALL mig_retry_ddl($q$ALTER TABLE orders ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID$q$);
CALL mig_retry_ddl($q$ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey$q$);

DROP PROCEDURE mig_retry_ddl(text);
```

```sql
-- M3: UNIQUE (external_ref) without blocking app writes
-- CREATE INDEX CONCURRENTLY takes only SHARE UPDATE EXCLUSIVE. It must not run under
-- lock_timeout, because it legitimately waits for the open analytics transaction to finish.
-- Remove any invalid leftover from a previous failed attempt first.
SET lock_timeout = 0;
DROP INDEX CONCURRENTLY IF EXISTS orders_external_ref_uidx;
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_uidx ON orders (external_ref);

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

-- Attaching an existing valid unique index is a brief ACCESS EXCLUSIVE operation (no scan).
SET lock_timeout = '100ms';
CALL mig_retry_ddl($q$ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_uidx$q$);

DROP PROCEDURE mig_retry_ddl(text);
```

```sql
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
```
