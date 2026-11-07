-- M3
-- CIC must wait for older transactions (the analytics txn); lock_timeout must not apply to that wait.
SET lock_timeout = 0;
SET max_parallel_maintenance_workers = 4;
SET maintenance_work_mem = '512MB';
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_uq ON orders(external_ref);

SET lock_timeout = '50ms';
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key
        UNIQUE USING INDEX orders_external_ref_uq;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 250 THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;
