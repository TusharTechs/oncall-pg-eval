```sql
-- migrator has statement_timeout = 3s; override for this session only.
SET statement_timeout = 0;

-- 1. Clean up leftover invalid indexes from the failed attempt (e.g. interrupted CIC).
SELECT format('DROP INDEX CONCURRENTLY IF EXISTS %s', indexrelid::regclass)
  FROM pg_index
 WHERE indrelid = 'orders'::regclass AND NOT indisvalid
\gexec

-- 2. Build the unique index only if no valid, plain unique index on (external_ref) exists yet.
SELECT NOT EXISTS (
  SELECT 1
    FROM pg_index ix
   WHERE ix.indrelid = 'orders'::regclass
     AND ix.indisunique AND ix.indisvalid
     AND ix.indnatts = 1
     AND ix.indpred IS NULL AND ix.indexprs IS NULL
     AND ix.indkey[0] = (SELECT attnum FROM pg_attribute
                          WHERE attrelid = 'orders'::regclass AND attname = 'external_ref')
) AS need_idx \gset

\if :need_idx
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_uq ON orders (external_ref);
\endif

-- 3. Attach as a unique constraint unless one already exists; retry on short lock_timeout
--    so we never queue behind the analytics transaction and block the app.
DO $$
DECLARE
  n int;
  attn smallint;
  idx name;
BEGIN
  SELECT attnum INTO attn FROM pg_attribute
   WHERE attrelid = 'orders'::regclass AND attname = 'external_ref';

  IF EXISTS (SELECT 1 FROM pg_constraint
              WHERE conrelid = 'orders'::regclass AND contype = 'u' AND conkey = ARRAY[attn]) THEN
    RETURN;
  END IF;

  SELECT c.relname INTO idx
    FROM pg_index ix JOIN pg_class c ON c.oid = ix.indexrelid
   WHERE ix.indrelid = 'orders'::regclass
     AND ix.indisunique AND ix.indisvalid
     AND ix.indnatts = 1 AND ix.indkey[0] = attn
     AND ix.indpred IS NULL AND ix.indexprs IS NULL
     AND NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conindid = ix.indexrelid)
   LIMIT 1;

  IF idx IS NULL THEN
    RAISE EXCEPTION 'no usable unique index on orders(external_ref)';
  END IF;

  FOR n IN 1..200 LOOP
    BEGIN
      SET LOCAL lock_timeout = '100ms';
      EXECUTE format('ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX %I', idx);
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      PERFORM pg_sleep(0.15);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock on orders to attach unique constraint';
END
$$;
```
