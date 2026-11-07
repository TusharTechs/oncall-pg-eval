```sql
-- Constant default => metadata-only ADD COLUMN (no rewrite). The only risk is the
-- ACCESS EXCLUSIVE lock queueing behind the long analytics transaction and
-- blocking the app, so try with a tiny lock_timeout and retry until a gap appears.
DO $$
DECLARE
  i int;
BEGIN
  FOR i IN 1..120 LOOP
    BEGIN
      SET LOCAL lock_timeout = '100ms';
      ALTER TABLE orders ADD COLUMN IF NOT EXISTS region text NOT NULL DEFAULT 'EU';
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      PERFORM pg_sleep(0.2);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not get lock on orders to add region';
END
$$;
```
