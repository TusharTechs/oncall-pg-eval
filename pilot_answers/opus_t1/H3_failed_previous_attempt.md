```sql
-- H3: UNIQUE(external_ref) on orders, idempotent w.r.t. an unknown partial previous attempt.
-- Role has statement_timeout=3s: override for this session only.
SET statement_timeout = 0;
SET lock_timeout = 0;

-- 1. Drop any invalid indexes on orders left behind (e.g. interrupted CREATE INDEX CONCURRENTLY).
--    DROP INDEX CONCURRENTLY only takes SHARE UPDATE EXCLUSIVE, so app traffic is not blocked.
SELECT format('DROP INDEX CONCURRENTLY IF EXISTS %s', i.indexrelid::regclass)
FROM pg_index i
WHERE i.indrelid = 'public.orders'::regclass
  AND NOT i.indisvalid
\gexec

-- 2. Inspect current state.
SELECT a.attnum AS ext_attnum
FROM pg_attribute a
WHERE a.attrelid = 'public.orders'::regclass
  AND a.attname = 'external_ref'
  AND NOT a.attisdropped
\gset

SELECT EXISTS (
  SELECT 1
  FROM pg_constraint c
  JOIN pg_index i ON i.indexrelid = c.conindid
  WHERE c.conrelid = 'public.orders'::regclass
    AND c.contype = 'u'
    AND c.conkey = ARRAY[:ext_attnum]::int2[]
    AND i.indisvalid
) AS have_constraint
\gset

\if :have_constraint
  \echo 'Unique constraint on orders(external_ref) already exists; nothing to do.'
\else
  -- Look for a valid, plain unique btree index on exactly (external_ref) that is not yet a constraint
  -- (previous attempt may have built it before failing).
  SELECT coalesce(min(c.relname)::text, '') AS reuse_idx,
         count(*) > 0 AS have_reuse
  FROM pg_index i
  JOIN pg_class c     ON c.oid = i.indexrelid
  JOIN pg_am am       ON am.oid = c.relam
  JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = :ext_attnum
  JOIN pg_opclass oc  ON oc.oid = i.indclass[0]
  WHERE i.indrelid = 'public.orders'::regclass
    AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive
    AND am.amname = 'btree'
    AND i.indnatts = 1 AND i.indnkeyatts = 1
    AND i.indkey[0] = :ext_attnum
    AND i.indexprs IS NULL AND i.indpred IS NULL
    AND i.indoption[0] = 0
    AND oc.opcdefault
    AND i.indcollation[0] = a.attcollation
    AND NOT EXISTS (SELECT 1 FROM pg_constraint k
                    WHERE k.conindid = i.indexrelid AND k.conrelid = i.indrelid)
  \gset

  \if :have_reuse
    \echo 'Reusing existing valid unique index' :reuse_idx
    SELECT set_config('migr.idx', :'reuse_idx', false);
  \else
    SELECT CASE
             WHEN to_regclass('public.orders_external_ref_key') IS NULL
              AND NOT EXISTS (SELECT 1 FROM pg_constraint
                              WHERE conrelid = 'public.orders'::regclass
                                AND conname = 'orders_external_ref_key')
             THEN 'orders_external_ref_key'
             ELSE 'orders_external_ref_key_' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS')
           END AS new_idx
    \gset
    -- Online build: SHARE UPDATE EXCLUSIVE, does not block app INSERT/UPDATE.
    CREATE UNIQUE INDEX CONCURRENTLY :"new_idx" ON public.orders (external_ref);
    SELECT set_config('migr.idx', :'new_idx', false);
  \endif

  -- 3. Attach the index as a UNIQUE constraint (metadata only, brief ACCESS EXCLUSIVE).
  --    Short lock_timeout + retry so we never queue the app behind the analytics transaction.
  SET lock_timeout = '100ms';
  DO $$
  DECLARE
    v_idx text := current_setting('migr.idx');
    n int := 0;
  BEGIN
    LOOP
      BEGIN
        EXECUTE format('ALTER TABLE public.orders ADD CONSTRAINT %I UNIQUE USING INDEX %I',
                       v_idx, v_idx);
        EXIT;
      EXCEPTION WHEN lock_not_available THEN
        n := n + 1;
        IF n >= 200 THEN RAISE; END IF;
        PERFORM pg_sleep(0.2);
      END;
    END LOOP;
  END $$;
  SET lock_timeout = 0;
\endif

-- 4. Final assertions.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_index
             WHERE indrelid = 'public.orders'::regclass AND NOT indisvalid) THEN
    RAISE EXCEPTION 'invalid index remains on orders';
  END IF;
  IF NOT EXISTS (
       SELECT 1
       FROM pg_constraint c
       JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attname = 'external_ref'
       JOIN pg_index i ON i.indexrelid = c.conindid
       WHERE c.conrelid = 'public.orders'::regclass
         AND c.contype = 'u'
         AND c.conkey = ARRAY[a.attnum]
         AND i.indisvalid) THEN
    RAISE EXCEPTION 'unique constraint on orders(external_ref) missing';
  END IF;
END $$;

RESET lock_timeout;
```
