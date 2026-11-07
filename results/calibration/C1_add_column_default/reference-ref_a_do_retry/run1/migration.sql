-- Reference A: short lock wait, generous pause between attempts (low lock-queue duty cycle).
SET lock_timeout = '50ms';
DO $$
BEGIN
  FOR i IN 1..400 LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU';   -- constant default: metadata-only on PG11+
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      PERFORM pg_sleep(0.2);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock on orders';
END $$;
