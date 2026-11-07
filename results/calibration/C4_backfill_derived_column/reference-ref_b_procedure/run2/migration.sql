-- Reference B (independent style): trigger on every UPDATE, keyset batches via a procedure with COMMIT,
-- CHECK added NOT VALID together with the column (one short lock), NOWAIT retries with jitter.
CREATE FUNCTION pg_temp.try(stmt text) RETURNS boolean LANGUAGE plpgsql AS $f$
BEGIN SET LOCAL lock_timeout = '30ms'; EXECUTE stmt; RETURN true;
EXCEPTION WHEN lock_not_available THEN RETURN false; END $f$;
CREATE FUNCTION orders_cents_sync() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.amount_cents := (NEW.amount * 100)::bigint; RETURN NEW; END $$;
DO $$ BEGIN
  FOR i IN 1..600 LOOP
    EXIT WHEN pg_temp.try('ALTER TABLE orders ADD COLUMN amount_cents bigint, ADD CONSTRAINT cents_nn CHECK (amount_cents IS NOT NULL) NOT VALID; CREATE TRIGGER orders_cents_trg BEFORE INSERT OR UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION orders_cents_sync()');
    PERFORM pg_sleep(0.15 + random()*0.1);
  END LOOP;
END $$;
CREATE PROCEDURE pg_temp.backfill() LANGUAGE plpgsql AS $$
DECLARE last_id bigint := 0; n int;
BEGIN
  LOOP
    WITH b AS (SELECT id FROM orders WHERE id > last_id ORDER BY id LIMIT 10000),
         u AS (UPDATE orders o SET amount_cents = (o.amount * 100)::bigint FROM b WHERE o.id = b.id AND o.amount_cents IS NULL RETURNING 1)
    SELECT max(b.id), (SELECT count(*) FROM u) INTO last_id, n FROM b;
    EXIT WHEN last_id IS NULL;
    COMMIT;
  END LOOP;
END $$;
CALL pg_temp.backfill();
ALTER TABLE orders VALIDATE CONSTRAINT cents_nn;
DO $$ BEGIN
  FOR i IN 1..600 LOOP EXIT WHEN pg_temp.try('ALTER TABLE orders ALTER COLUMN amount_cents SET NOT NULL'); PERFORM pg_sleep(0.15 + random()*0.1); END LOOP;
END $$;
