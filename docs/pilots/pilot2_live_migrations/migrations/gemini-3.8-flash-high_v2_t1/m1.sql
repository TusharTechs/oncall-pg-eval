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

SET lock_timeout = '200ms';

DO $$
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU';
      EXIT;
    EXCEPTION
      WHEN lock_not_available THEN
        PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;

RESET lock_timeout;
