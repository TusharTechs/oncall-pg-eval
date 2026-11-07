```sql
-- Retry helper: ACCESS EXCLUSIVE DDL must never queue behind the long analytics
-- transaction (it would block all app traffic), so use a tiny lock_timeout and retry.
CREATE FUNCTION pg_temp.ddl_retry(stmt text, max_tries int DEFAULT 300)
RETURNS void LANGUAGE plpgsql
SET lock_timeout = '30ms'
AS $$
BEGIN
  FOR i IN 1..max_tries LOOP
    BEGIN
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock for: %', stmt;
END
$$;

-- Constant default on PG11+ is metadata-only (no table rewrite).
SELECT pg_temp.ddl_retry($q$ALTER TABLE public.orders ADD COLUMN region text NOT NULL DEFAULT 'EU'$q$);
```
