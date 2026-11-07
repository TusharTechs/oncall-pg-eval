SET lock_timeout = 0;
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders(external_ref);
SET lock_timeout = '150ms';
DO $$ BEGIN
  FOR i IN 1..150 LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock';
END $$;
