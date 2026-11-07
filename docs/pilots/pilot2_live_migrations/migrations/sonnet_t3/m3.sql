-- M3
SET lock_timeout = 0;
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_uq ON orders(external_ref);

SET lock_timeout = '50ms';
DO $$
BEGIN
  FOR i IN 1..150 LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key
        UNIQUE USING INDEX orders_external_ref_uq;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF i = 150 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;
RESET lock_timeout;
