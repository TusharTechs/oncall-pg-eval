```sql
-- 1. Build the unique index without blocking writes (autocommit, outside any transaction).
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_uq ON orders (external_ref);

-- 2. Attach it as a constraint. This needs a brief ACCESS EXCLUSIVE lock, so use a
--    short lock_timeout and retry rather than queueing behind the analytics transaction.
DO $$
DECLARE
  i int;
BEGIN
  FOR i IN 1..200 LOOP
    BEGIN
      SET LOCAL lock_timeout = '100ms';
      ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_uq;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      PERFORM pg_sleep(0.15);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock on orders to attach unique constraint';
END
$$;
```
