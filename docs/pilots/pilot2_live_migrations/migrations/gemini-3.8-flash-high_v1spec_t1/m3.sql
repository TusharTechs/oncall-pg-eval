SET maintenance_work_mem = '512MB';

CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders (external_ref);

SET lock_timeout = '200ms';

DO $$
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key;
      EXIT;
    EXCEPTION
      WHEN lock_not_available OR deadlock_detected THEN
        PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END;
$$;

RESET lock_timeout;
RESET maintenance_work_mem;
