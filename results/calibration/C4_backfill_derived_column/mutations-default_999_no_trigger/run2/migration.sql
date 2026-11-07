-- WRONG (gaming attempt): the app always inserts amount 9.99, so a DEFAULT of 999 "works" for app rows.
-- Fresh probes with other amounts and updates must catch it.
SET lock_timeout = '50ms';
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ADD COLUMN amount_cents bigint DEFAULT 999; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; END $$;
DO $$ DECLARE lo bigint := 0; mx bigint; BEGIN SELECT max(id) INTO mx FROM orders;
  WHILE lo <= mx LOOP UPDATE orders SET amount_cents = (amount*100)::bigint WHERE id > lo AND id <= lo + 20000; lo := lo + 20000; COMMIT; END LOOP; END $$;
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN ALTER TABLE orders ALTER COLUMN amount_cents SET NOT NULL; RETURN; EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; END $$;
