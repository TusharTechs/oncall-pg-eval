-- Reference B (independent style): the FK may be added NOT VALID *before* the repair: RI triggers only check rows whose
-- key changes and skip NULL keys, so the app's qty updates are unaffected. Then keyset repair via a procedure,
-- then CHECK -> VALIDATE -> SET NOT NULL, all with NOWAIT-style retries.
CREATE FUNCTION pg_temp.try(stmt text) RETURNS boolean LANGUAGE plpgsql AS $f$
BEGIN SET LOCAL lock_timeout = '30ms'; EXECUTE stmt; RETURN true;
EXCEPTION WHEN lock_not_available THEN RETURN false; END $f$;
DO $$ BEGIN
  FOR i IN 1..600 LOOP
    IF pg_temp.try('ALTER TABLE orders ADD CONSTRAINT c_fk FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID') THEN RETURN; END IF;
    PERFORM pg_sleep(0.15 + random()*0.1);
  END LOOP; RAISE EXCEPTION 'could not acquire lock';
END $$;
CREATE PROCEDURE pg_temp.repair() LANGUAGE plpgsql AS $$
DECLARE last_id bigint := 0;
BEGIN
  LOOP
    WITH b AS (SELECT order_id, customer_id FROM legacy_customer_map WHERE order_id > last_id ORDER BY order_id LIMIT 5000),
         u AS (UPDATE orders o SET customer_id = b.customer_id FROM b WHERE o.id = b.order_id AND o.customer_id IS NULL RETURNING 1)
    SELECT max(b.order_id) INTO last_id FROM b;
    EXIT WHEN last_id IS NULL;
    COMMIT;
  END LOOP;
END $$;
CALL pg_temp.repair();
ALTER TABLE orders VALIDATE CONSTRAINT c_fk;
DO $$ BEGIN
  FOR i IN 1..600 LOOP
    IF pg_temp.try('ALTER TABLE orders ADD CONSTRAINT c_nn CHECK (customer_id IS NOT NULL) NOT VALID') THEN RETURN; END IF;
    PERFORM pg_sleep(0.15 + random()*0.1);
  END LOOP; RAISE EXCEPTION 'could not acquire lock';
END $$;
ALTER TABLE orders VALIDATE CONSTRAINT c_nn;
DO $$ BEGIN
  FOR i IN 1..600 LOOP IF pg_temp.try('ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL') THEN RETURN; END IF; PERFORM pg_sleep(0.15 + random()*0.1); END LOOP;
  RAISE EXCEPTION 'could not acquire lock';
END $$;
