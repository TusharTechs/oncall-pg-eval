```sql
-- C3: UNIQUE constraint on orders(external_ref), online.
-- 1. Build the unique index CONCURRENTLY (SHARE UPDATE EXCLUSIVE: never blocks
--    app writes or analytics reads). CIC internally waits for older transactions
--    (including the 6-12s analytics txn) via lock waits, so lock_timeout must be
--    disabled for it, otherwise it aborts and leaves an INVALID index.
-- 2. Attach it as a constraint with ADD CONSTRAINT ... USING INDEX, which needs a
--    momentary ACCESS EXCLUSIVE lock: taken with a short lock_timeout + retry so we
--    never queue behind the analytics transaction (and make the app queue behind us).

SET statement_timeout = 0;

-- Clean up any leftover invalid index from an earlier attempt (no-op normally).
SET lock_timeout = 0;
DROP INDEX CONCURRENTLY IF EXISTS orders_external_ref_key;

CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders (external_ref);

-- Attach the index as a UNIQUE constraint.
SET lock_timeout = '100ms';

DO $$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '30 seconds';
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$$;

RESET lock_timeout;
```
