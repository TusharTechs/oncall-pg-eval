SET lock_timeout = '50ms';
DO $$
BEGIN
  FOR i IN 1..300 LOOP
    BEGIN
      ALTER SEQUENCE events_id_seq MINVALUE -2147483648 RESTART WITH -2147483648;
      RETURN;
    EXCEPTION
      WHEN lock_not_available THEN
        PERFORM pg_sleep(0.05);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not alter sequence';
END $$;
