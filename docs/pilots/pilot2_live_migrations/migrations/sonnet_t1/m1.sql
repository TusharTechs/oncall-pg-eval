-- M1
SET lock_timeout = '50ms';
DO $$
DECLARE i int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU';
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      i := i + 1;
      IF i > 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;
RESET lock_timeout;
