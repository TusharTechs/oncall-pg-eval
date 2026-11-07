SET lock_timeout = '150ms';
DO $$ BEGIN
  FOR i IN 1..150 LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU';
      RETURN;
    EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.01);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock';
END $$;
