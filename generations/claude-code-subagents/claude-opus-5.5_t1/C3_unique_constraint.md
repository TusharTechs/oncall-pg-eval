```sql
-- C3: UNIQUE constraint on orders(external_ref)
-- Build the unique index CONCURRENTLY (SHARE UPDATE EXCLUSIVE: app DML continues),
-- then attach it as a constraint, which needs only a brief strong lock. That attach
-- step uses a short lock_timeout with retries so it never queues behind the long
-- analytics transactions (which would stall app writes queued behind it).
-- lock_timeout stays 0 for CREATE INDEX CONCURRENTLY: its internal waits for older
-- transactions are lock waits and would otherwise fail and leave an invalid index.

SET statement_timeout = 0;
SET lock_timeout = 0;

CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders (external_ref);

DO $$
DECLARE
  deadline constant timestamptz := clock_timestamp() + interval '30 seconds';
BEGIN
  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key;
      EXIT;
    EXCEPTION WHEN lock_not_available OR deadlock_detected THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;
```
