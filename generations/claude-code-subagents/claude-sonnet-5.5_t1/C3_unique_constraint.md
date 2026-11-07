```sql
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

-- Build the unique index without blocking writes (lock_timeout is 0 at session level here).
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON public.orders (external_ref);

-- Attach it as a constraint; this needs a brief ACCESS EXCLUSIVE lock, so retry with a tiny timeout.
SELECT pg_temp.ddl_retry($q$ALTER TABLE public.orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key$q$);
```
