```sql
-- Build the index without blocking writes (lock_timeout must be off: CIC waits on other transactions).
RESET lock_timeout;
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders (external_ref);

-- Attach it as a constraint; this needs a brief ACCESS EXCLUSIVE lock, so retry with a short lock_timeout.
SET lock_timeout = '50ms';

DO $$
DECLARE
  i int;
BEGIN
  FOR i IN 1..150 LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF i = 150 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;

RESET lock_timeout;
```
