```sql
-- C1: add orders.region text NOT NULL DEFAULT 'EU'
-- On PG11+ a non-volatile default is stored as a "missing value" in the catalog:
-- no table rewrite, no scan. The only cost is a brief ACCESS EXCLUSIVE lock.
-- The analytics job holds ACCESS SHARE for 6-12 s at a time, so we must never sit
-- in the lock queue (app writes would queue behind us). Use a short lock_timeout
-- and retry until we hit a gap between analytics transactions.

SET statement_timeout = 0;

DO $$
DECLARE
  deadline constant timestamptz := clock_timestamp() + interval '40 seconds';
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU';
      EXIT;
    EXCEPTION WHEN lock_not_available OR deadlock_detected THEN
      IF clock_timestamp() > deadline THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;
```
