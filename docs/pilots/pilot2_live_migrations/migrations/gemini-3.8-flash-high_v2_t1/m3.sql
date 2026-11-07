DO $$
BEGIN
  LOOP
    EXIT WHEN NOT EXISTS (
      SELECT 1
      FROM pg_locks
      WHERE relation = 'orders'::regclass
        AND mode = 'AccessShareLock'
        AND pid <> pg_backend_pid()
    );
    PERFORM pg_sleep(0.1);
  END LOOP;
END $$;

CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_idx ON orders(external_ref);

SET lock_timeout = '200ms';

DO $$
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_idx;
      EXIT;
    EXCEPTION
      WHEN lock_not_available THEN
        PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;

RESET lock_timeout;
