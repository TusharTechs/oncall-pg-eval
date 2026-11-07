```sql
-- Ticket C3: UNIQUE constraint on orders(external_ref)
--
-- 1. Build the unique index CONCURRENTLY (SHARE UPDATE EXCLUSIVE: app reads/writes
--    and the analytics reader are never blocked; it merely waits for them).
-- 2. Attach it as a constraint with ADD CONSTRAINT ... USING INDEX: metadata only,
--    but needs a brief ACCESS EXCLUSIVE lock, so take it with a short lock_timeout
--    and retry until we hit a gap between analytics transactions.

SET statement_timeout = 0;
SET lock_timeout = 0;   -- CIC's internal waits on other transactions honour lock_timeout

CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders (external_ref);

SET lock_timeout = '50ms';
DO $$
DECLARE
  attempts int := 0;
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders
        ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      attempts := attempts + 1;
      IF attempts >= 150 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.15 + random() * 0.1);
    END;
  END LOOP;
END
$$;

RESET lock_timeout;
```
