-- M1: orders.region text NOT NULL DEFAULT 'EU'
SET lock_timeout = '100ms';

CREATE FUNCTION pg_temp.retry_ddl(stmt text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '30 seconds';
BEGIN
  LOOP
    BEGIN
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() >= deadline THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

SELECT pg_temp.retry_ddl('ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT ''EU''');
