-- WRONG: one giant UPDATE holds row locks on all 5M rows for its whole duration; app UPDATEs block.
SET lock_timeout = '50ms';
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ADD COLUMN amount_cents bigint; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; END $$;
CREATE FUNCTION orders_set_amount_cents() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.amount_cents := (NEW.amount * 100)::bigint; RETURN NEW; END $$;
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN CREATE TRIGGER t BEFORE INSERT OR UPDATE OF amount ON orders FOR EACH ROW EXECUTE FUNCTION orders_set_amount_cents(); RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; END $$;
SET lock_timeout = 0;
UPDATE orders SET amount_cents = (amount * 100)::bigint WHERE amount_cents IS NULL;
SET lock_timeout = '50ms';
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ADD CONSTRAINT nn CHECK (amount_cents IS NOT NULL) NOT VALID; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; END $$;
ALTER TABLE orders VALIDATE CONSTRAINT nn;
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ALTER COLUMN amount_cents SET NOT NULL; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; END $$;
