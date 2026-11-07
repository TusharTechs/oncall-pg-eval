```sql
-- Idempotent: works from any state left by the failed attempt.
SET statement_timeout = 0;

-- 1. Drop any invalid indexes left on orders (retry around the brief table lock).
SET lock_timeout = '50ms';

DO $$
DECLARE
  r record;
  i int;
BEGIN
  FOR r IN
    SELECT n.nspname, c.relname
    FROM pg_index x
    JOIN pg_class c ON c.oid = x.indexrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE x.indrelid = 'orders'::regclass AND NOT x.indisvalid
  LOOP
    FOR i IN 1..150 LOOP
      BEGIN
        EXECUTE format('DROP INDEX IF EXISTS %I.%I', r.nspname, r.relname);
        EXIT;
      EXCEPTION WHEN lock_not_available THEN
        IF i = 150 THEN
          RAISE;
        END IF;
        PERFORM pg_sleep(0.1);
      END;
    END LOOP;
  END LOOP;
END
$$;

RESET lock_timeout;

-- 2. Build a unique index concurrently only if no valid plain unique index on (external_ref) exists yet.
SELECT 'CREATE UNIQUE INDEX CONCURRENTLY orders_extref_uniq_h3 ON orders (external_ref)'
WHERE NOT EXISTS (
  SELECT 1 FROM pg_index x
  WHERE x.indrelid = 'orders'::regclass
    AND x.indisunique AND x.indisvalid AND x.indimmediate
    AND x.indnatts = 1
    AND x.indkey[0] = (SELECT attnum FROM pg_attribute
                       WHERE attrelid = 'orders'::regclass AND attname = 'external_ref')
    AND x.indpred IS NULL AND x.indexprs IS NULL
)
\gexec

-- 3. Attach as a unique constraint if one does not already exist (retry around the brief lock).
SET lock_timeout = '50ms';

DO $$
DECLARE
  attn smallint;
  idx name;
  i int;
BEGIN
  SELECT attnum INTO attn FROM pg_attribute
  WHERE attrelid = 'orders'::regclass AND attname = 'external_ref';

  IF EXISTS (SELECT 1 FROM pg_constraint c
             WHERE c.conrelid = 'orders'::regclass AND c.contype = 'u'
               AND c.conkey = ARRAY[attn]) THEN
    RETURN;
  END IF;

  SELECT ic.relname INTO idx
  FROM pg_index x
  JOIN pg_class ic ON ic.oid = x.indexrelid
  WHERE x.indrelid = 'orders'::regclass
    AND x.indisunique AND x.indisvalid AND x.indimmediate
    AND x.indnatts = 1 AND x.indkey[0] = attn
    AND x.indpred IS NULL AND x.indexprs IS NULL
    AND NOT EXISTS (SELECT 1 FROM pg_constraint c2 WHERE c2.conindid = x.indexrelid)
  LIMIT 1;

  IF idx IS NULL THEN
    RAISE EXCEPTION 'no valid unique index on orders(external_ref) found';
  END IF;

  FOR i IN 1..150 LOOP
    BEGIN
      EXECUTE format('ALTER TABLE orders ADD CONSTRAINT orders_external_ref_h3_key UNIQUE USING INDEX %I', idx);
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
