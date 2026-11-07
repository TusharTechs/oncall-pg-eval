```sql
-- Constant default: metadata-only in PG 11+, no table rewrite.
-- The ALTER needs ACCESS EXCLUSIVE briefly, so never queue behind the analytics
-- transaction: use a short lock_timeout and retry until we catch a gap.
SET lock_timeout = '50ms';

DO $$
DECLARE
  i int;
BEGIN
  FOR i IN 1..150 LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU';
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
