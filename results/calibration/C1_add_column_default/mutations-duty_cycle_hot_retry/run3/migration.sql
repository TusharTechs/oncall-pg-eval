-- WRONG (subtle): textbook retry, but a 175 ms lock wait with a 10 ms pause keeps an ACCESS EXCLUSIVE
-- request in the queue ~95% of the time, so app writes are starved while the reader is open.
SET lock_timeout = '175ms';
DO $$
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU';
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      PERFORM pg_sleep(0.01);
    END;
  END LOOP;
END $$;
