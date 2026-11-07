-- WRONG (subtle): INSERT-only trigger; later UPDATEs of amount leave amount_cents stale.
-- committed backfill, then NOT NULL via a validated CHECK. Every ACCESS EXCLUSIVE step: short wait + retry.
SET lock_timeout = '50ms';
CREATE FUNCTION pg_temp.retry(stmt text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  FOR i IN 1..600 LOOP
    BEGIN EXECUTE stmt; RETURN;
    EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock: %', stmt;
END $$;
CREATE FUNCTION orders_set_amount_cents() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.amount_cents := (NEW.amount * 100)::bigint; RETURN NEW; END $$;
SELECT pg_temp.retry('ALTER TABLE orders ADD COLUMN amount_cents bigint');
SELECT pg_temp.retry('CREATE TRIGGER orders_amount_cents_trg BEFORE INSERT ON orders FOR EACH ROW EXECUTE FUNCTION orders_set_amount_cents()');
DO $$
DECLARE lo bigint := 0; mx bigint;
BEGIN
  SELECT max(id) INTO mx FROM orders;
  WHILE lo <= mx LOOP
    UPDATE orders SET amount_cents = (amount * 100)::bigint WHERE id > lo AND id <= lo + 20000 AND amount_cents IS NULL;
    lo := lo + 20000;
    COMMIT;
  END LOOP;
END $$;
SELECT pg_temp.retry('ALTER TABLE orders ADD CONSTRAINT orders_amount_cents_nn CHECK (amount_cents IS NOT NULL) NOT VALID');
SET lock_timeout = 0;
ALTER TABLE orders VALIDATE CONSTRAINT orders_amount_cents_nn;
SET lock_timeout = '50ms';
SELECT pg_temp.retry('ALTER TABLE orders ALTER COLUMN amount_cents SET NOT NULL');
SELECT pg_temp.retry('ALTER TABLE orders DROP CONSTRAINT orders_amount_cents_nn');
