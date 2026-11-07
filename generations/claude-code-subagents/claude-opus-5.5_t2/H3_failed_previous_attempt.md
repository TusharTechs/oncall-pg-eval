```sql
-- Ticket H3: UNIQUE constraint on orders(external_ref), recovering from a
-- partially-completed earlier attempt (unknown state).
--
-- Idempotent plan:
--   0. Override the role's 3s statement_timeout for this session.
--   1. Drop every invalid index left on orders (DROP INDEX CONCURRENTLY: non-blocking).
--   2. If the constraint already exists -> nothing to build.
--      Else if a valid, unattached unique btree index on exactly (external_ref) exists -> reuse it.
--      Else build one with CREATE UNIQUE INDEX CONCURRENTLY.
--   3. Attach it via ADD CONSTRAINT ... USING INDEX (brief ACCESS EXCLUSIVE lock,
--      short lock_timeout + retry so it never queues behind the analytics reader).
--   4. Assert the end state.

SET statement_timeout = 0;
SET lock_timeout = 0;   -- concurrent index ops wait on other xacts; those waits honour lock_timeout

-- 1. Remove leftover invalid indexes on orders
SELECT format('DROP INDEX CONCURRENTLY IF EXISTS %s', i.indexrelid::regclass)
  FROM pg_index i
 WHERE i.indrelid = 'orders'::regclass
   AND NOT i.indisvalid
\gexec

-- 2. Inspect current state
SELECT
  EXISTS (
    SELECT 1
      FROM pg_constraint c
     WHERE c.conrelid = 'orders'::regclass
       AND c.contype = 'u'
       AND c.conkey = ARRAY[(SELECT a.attnum FROM pg_attribute a
                              WHERE a.attrelid = 'orders'::regclass
                                AND a.attname = 'external_ref')]
  ) AS has_constraint,
  EXISTS (
    SELECT 1
      FROM pg_index i
      JOIN pg_class ic ON ic.oid = i.indexrelid
      JOIN pg_am am    ON am.oid = ic.relam
     WHERE i.indrelid = 'orders'::regclass
       AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive
       AND i.indnatts = 1
       AND i.indkey[0] = (SELECT a.attnum FROM pg_attribute a
                           WHERE a.attrelid = 'orders'::regclass
                             AND a.attname = 'external_ref')
       AND i.indexprs IS NULL
       AND i.indpred IS NULL
       AND am.amname = 'btree'
       AND i.indoption[0] = 0
       AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = i.indexrelid)
  ) AS has_index,
  CASE WHEN to_regclass('orders_external_ref_key') IS NULL
       THEN 'orders_external_ref_key'
       ELSE 'orders_external_ref_key_' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS')
  END AS new_index_name
\gset

\if :has_constraint
  \echo 'unique constraint on orders(external_ref) already present'
\elif :has_index
  \echo 'reusing existing valid unique index on orders(external_ref)'
\else
CREATE UNIQUE INDEX CONCURRENTLY :"new_index_name" ON orders (external_ref);
\endif

-- 3. Attach the index as the constraint (no-op if constraint already exists)
DO $$
DECLARE
  attnum_ref smallint;
  idx        text;
  attempts   int := 0;
BEGIN
  SELECT a.attnum INTO attnum_ref
    FROM pg_attribute a
   WHERE a.attrelid = 'orders'::regclass AND a.attname = 'external_ref';

  IF EXISTS (SELECT 1 FROM pg_constraint c
              WHERE c.conrelid = 'orders'::regclass
                AND c.contype = 'u'
                AND c.conkey = ARRAY[attnum_ref]) THEN
    RETURN;
  END IF;

  SELECT ic.relname INTO idx
    FROM pg_index i
    JOIN pg_class ic ON ic.oid = i.indexrelid
    JOIN pg_am am    ON am.oid = ic.relam
   WHERE i.indrelid = 'orders'::regclass
     AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive
     AND i.indnatts = 1
     AND i.indkey[0] = attnum_ref
     AND i.indexprs IS NULL
     AND i.indpred IS NULL
     AND am.amname = 'btree'
     AND i.indoption[0] = 0
     AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = i.indexrelid)
   ORDER BY ic.relname
   LIMIT 1;

  IF idx IS NULL THEN
    RAISE EXCEPTION 'no valid unique index on orders(external_ref) to attach';
  END IF;

  PERFORM set_config('lock_timeout', '50ms', true);
  LOOP
    BEGIN
      EXECUTE format('ALTER TABLE orders ADD CONSTRAINT %I UNIQUE USING INDEX %I', idx, idx);
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

-- 4. Verify end state
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c
                   JOIN pg_index i ON i.indexrelid = c.conindid
                  WHERE c.conrelid = 'orders'::regclass
                    AND c.contype = 'u'
                    AND i.indisvalid
                    AND c.conkey = ARRAY[(SELECT a.attnum FROM pg_attribute a
                                           WHERE a.attrelid = 'orders'::regclass
                                             AND a.attname = 'external_ref')]) THEN
    RAISE EXCEPTION 'unique constraint on orders(external_ref) missing';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_index WHERE indrelid = 'orders'::regclass AND NOT indisvalid) THEN
    RAISE EXCEPTION 'invalid index remains on orders';
  END IF;
END
$$;
```
