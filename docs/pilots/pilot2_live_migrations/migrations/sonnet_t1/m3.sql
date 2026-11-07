-- M3
-- CONCURRENTLY: does not block app writes (it waits for the open analytics txn, which is fine)
SET lock_timeout = 0;
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_uq_idx ON orders (external_ref);

SET lock_timeout = '50ms';
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_external_ref_uq
        UNIQUE USING INDEX orders_external_ref_uq_idx;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;
RESET lock_timeout;
