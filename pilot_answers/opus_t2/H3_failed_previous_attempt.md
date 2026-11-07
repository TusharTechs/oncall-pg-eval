```sql
-- H3: UNIQUE constraint on orders(external_ref), idempotent against an unknown
-- partially-completed previous attempt.
-- The role has statement_timeout = 3s; override it for this session only.
SET statement_timeout = 0;
SET lock_timeout = '100ms';

-- Step 1: drop any invalid leftover indexes on orders (e.g. from a failed
-- CREATE UNIQUE INDEX CONCURRENTLY). All dropped in one brief ACCESS EXCLUSIVE
-- window, retried with a short lock_timeout so the app never queues behind the
-- analytics transaction for long.
DO $$
DECLARE
  r        record;
  attempts int := 0;
BEGIN
  LOOP
    BEGIN
      FOR r IN SELECT i.indexrelid::regclass AS idx
                 FROM pg_index i
                WHERE i.indrelid = 'orders'::regclass
                  AND NOT i.indisvalid
      LOOP
        EXECUTE format('DROP INDEX %s', r.idx);
      END LOOP;
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      attempts := attempts + 1;
      IF attempts >= 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05 + random() * 0.15);
    END;
  END LOOP;
END $$;

-- Step 2: build the unique index concurrently, unless a suitable valid unique
-- index on exactly external_ref already exists (previous attempt got that far).
-- CIC waits on other transactions' virtualxids, so lock_timeout must be off here.
SET lock_timeout = 0;
SELECT format('CREATE UNIQUE INDEX CONCURRENTLY %I ON orders (external_ref)',
              CASE WHEN to_regclass('orders_external_ref_key') IS NULL
                   THEN 'orders_external_ref_key'
                   ELSE 'orders_external_ref_uniq' END)
WHERE NOT EXISTS (
  SELECT 1
    FROM pg_index i
    JOIN pg_class ic    ON ic.oid = i.indexrelid
    JOIN pg_am am       ON am.oid = ic.relam
    JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attname = 'external_ref'
   WHERE i.indrelid = 'orders'::regclass
     AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive
     AND i.indnatts = 1 AND i.indkey[0] = a.attnum
     AND i.indpred IS NULL AND i.indexprs IS NULL
     AND am.amname = 'btree'
     AND i.indoption[0] = 0
     AND i.indcollation[0] = a.attcollation
     AND i.indclass[0] = (SELECT oc.oid FROM pg_opclass oc
                           WHERE oc.opcmethod = am.oid
                             AND oc.opcintype = a.atttypid
                             AND oc.opcdefault)
)
\gexec

-- Step 3: attach the constraint to the index (no scan; brief ACCESS EXCLUSIVE, retried).
-- No-op if the constraint already exists from the previous attempt.
SET lock_timeout = '100ms';
DO $$
DECLARE
  att      int2;
  idx      regclass;
  attempts int := 0;
BEGIN
  SELECT attnum INTO att FROM pg_attribute
   WHERE attrelid = 'orders'::regclass AND attname = 'external_ref' AND NOT attisdropped;

  IF EXISTS (SELECT 1 FROM pg_constraint
              WHERE conrelid = 'orders'::regclass AND contype = 'u'
                AND conkey = ARRAY[att]) THEN
    RAISE NOTICE 'unique constraint on orders(external_ref) already present';
    RETURN;
  END IF;

  SELECT i.indexrelid::regclass INTO idx
    FROM pg_index i
    JOIN pg_class ic    ON ic.oid = i.indexrelid
    JOIN pg_am am       ON am.oid = ic.relam
    JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = att
   WHERE i.indrelid = 'orders'::regclass
     AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive
     AND i.indnatts = 1 AND i.indkey[0] = att
     AND i.indpred IS NULL AND i.indexprs IS NULL
     AND am.amname = 'btree'
     AND i.indoption[0] = 0
     AND i.indcollation[0] = a.attcollation
     AND i.indclass[0] = (SELECT oc.oid FROM pg_opclass oc
                           WHERE oc.opcmethod = am.oid
                             AND oc.opcintype = a.atttypid
                             AND oc.opcdefault)
     AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = i.indexrelid)
   ORDER BY ic.relname
   LIMIT 1;

  IF idx IS NULL THEN
    RAISE EXCEPTION 'no suitable unique index on orders(external_ref) found';
  END IF;

  LOOP
    BEGIN
      EXECUTE format('ALTER TABLE orders ADD UNIQUE USING INDEX %I',
                     (SELECT relname FROM pg_class WHERE oid = idx));
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      attempts := attempts + 1;
      IF attempts >= 400 THEN RAISE; END IF;
      PERFORM pg_sleep(0.05 + random() * 0.15);
    END;
  END LOOP;
END $$;

RESET lock_timeout;
```
