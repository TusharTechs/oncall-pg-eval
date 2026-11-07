```sql
-- Ticket C1: add orders.region text NOT NULL DEFAULT 'EU'
--
-- On PG 11+ a non-volatile default is stored as the column's "missing value":
-- no table rewrite, and no NOT NULL verification scan (the missing value is non-NULL).
-- The only hazard is the brief ACCESS EXCLUSIVE lock: if it queues behind the
-- long analytics transaction, every app write queues behind *it*. So acquire it
-- with a short lock_timeout and retry until we land in a gap between analytics
-- transactions.

SET statement_timeout = 0;
SET lock_timeout = '50ms';

DO $$
DECLARE
  attempts int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU';
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      attempts := attempts + 1;
      IF attempts >= 120 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.15 + random() * 0.1);
    END;
  END LOOP;
END
$$;

RESET lock_timeout;
```
