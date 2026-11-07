SET lock_timeout = '200ms';

DO $$
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU';
      EXIT;
    EXCEPTION
      WHEN lock_not_available OR deadlock_detected THEN
        PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END;
$$;

RESET lock_timeout;
