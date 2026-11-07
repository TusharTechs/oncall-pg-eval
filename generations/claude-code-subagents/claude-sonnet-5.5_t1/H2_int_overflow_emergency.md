```sql
CREATE FUNCTION pg_temp.ddl_retry(stmt text, max_tries int DEFAULT 300)
RETURNS void LANGUAGE plpgsql
SET lock_timeout = '100ms'
AS $$
BEGIN
  FOR i IN 1..max_tries LOOP
    BEGIN
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock for: %', stmt;
END
$$;

-- The existing ids occupy the top ~2M values of the int range. The int range below
-- them (from -2147483648 upward) is completely unused: ~4.1 billion free values.
-- Move the identity sequence there. No row is rewritten and no id changes; the
-- column type change to bigint can be done later in a maintenance window.
-- ALTER SEQUENCE only locks the sequence, not the events table, so it does not
-- queue behind the analytics reader.
SELECT pg_temp.ddl_retry($q$ALTER SEQUENCE public.events_id_seq MINVALUE -2147483648 RESTART WITH -2147483648$q$);
```
