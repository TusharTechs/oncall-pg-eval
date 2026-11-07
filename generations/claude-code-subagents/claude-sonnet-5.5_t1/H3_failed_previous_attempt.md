```sql
-- Role has statement_timeout=3s; disable for this session only.
SET statement_timeout = 0;
SET lock_timeout = 0;

CREATE FUNCTION pg_temp.ddl_retry(stmt text, max_tries int DEFAULT 400)
RETURNS void LANGUAGE plpgsql
SET lock_timeout = '30ms'
AS $$
BEGIN
  FOR i IN 1..max_tries LOOP
    BEGIN
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock for: %', stmt;
END
$$;

-- 1. Clean up any invalid index left by the failed attempt (idempotent).
SELECT format('DROP INDEX CONCURRENTLY IF EXISTS %I.%I', n.nspname, c.relname)
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE i.indrelid = 'public.orders'::regclass
  AND NOT i.indisvalid
\gexec

-- 2. Build a valid unique index only if neither a constraint nor a usable valid
--    unique index on exactly external_ref already exists.
SELECT 'CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON public.orders (external_ref)'
WHERE NOT EXISTS (
  SELECT 1 FROM pg_index i
  WHERE i.indrelid = 'public.orders'::regclass
    AND i.indisunique AND i.indisvalid AND NOT i.indisprimary
    AND i.indnatts = 1
    AND i.indkey[0] = (SELECT attnum FROM pg_attribute
                       WHERE attrelid = 'public.orders'::regclass AND attname = 'external_ref')
    AND i.indpred IS NULL AND i.indexprs IS NULL
)
\gexec

-- 3. Attach as a constraint if no unique constraint on external_ref exists yet.
SELECT format('SELECT pg_temp.ddl_retry(%L)',
         format('ALTER TABLE public.orders ADD CONSTRAINT %I UNIQUE USING INDEX %I', c.relname, c.relname))
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
WHERE i.indrelid = 'public.orders'::regclass
  AND i.indisunique AND i.indisvalid AND i.indisready AND NOT i.indisprimary
  AND i.indnatts = 1
  AND i.indkey[0] = (SELECT attnum FROM pg_attribute
                     WHERE attrelid = 'public.orders'::regclass AND attname = 'external_ref')
  AND i.indpred IS NULL AND i.indexprs IS NULL
  AND NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conindid = i.indexrelid)
  AND NOT EXISTS (
    SELECT 1 FROM pg_constraint k
    WHERE k.conrelid = 'public.orders'::regclass AND k.contype = 'u'
      AND k.conkey = ARRAY[(SELECT attnum FROM pg_attribute
                            WHERE attrelid = 'public.orders'::regclass AND attname = 'external_ref')]::int2[]
  )
LIMIT 1
\gexec
```
