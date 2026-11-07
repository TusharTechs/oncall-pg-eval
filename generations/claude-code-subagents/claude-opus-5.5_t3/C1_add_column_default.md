```sql
-- C1: add orders.region text NOT NULL DEFAULT 'EU'
-- On PG11+ a constant default is metadata-only (no rewrite), but ALTER TABLE
-- still needs ACCESS EXCLUSIVE. The analytics job holds ACCESS SHARE for 6-12s,
-- so we must never wait in the lock queue for long (app would queue behind us).
-- Strategy: short lock_timeout + retry loop; each failed attempt is rolled back
-- in its own subtransaction (releasing its lock-queue position), and we succeed
-- in one of the 1-3s gaps between analytics transactions.

SET lock_timeout = '100ms';
SET statement_timeout = 0;

DO $$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '40 seconds';
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN IF NOT EXISTS region text NOT NULL DEFAULT 'EU';
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() > deadline THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

RESET lock_timeout;
```
