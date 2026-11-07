```sql
-- H3: UNIQUE constraint on orders(external_ref), idempotent against an unknown partial
-- state left by a previous failed attempt (e.g. an INVALID index from a failed
-- CREATE INDEX CONCURRENTLY, a valid unique index never attached, or the constraint
-- already present).
--
-- The role has statement_timeout = 3s: override it for this session only.
-- lock_timeout stays 0 for CREATE INDEX CONCURRENTLY (its waits for older transactions are
-- lock waits; a timeout there would leave yet another invalid index). Only the final
-- short ACCESS EXCLUSIVE window uses lock_timeout + retry, so app writes never queue
-- behind us while analytics holds its long ACCESS SHARE lock.

SET statement_timeout = 0;
SET lock_timeout = 0;

-- 1. Inspect current state.
SELECT
  EXISTS (
    SELECT 1
    FROM pg_constraint con
    JOIN pg_index i ON i.indexrelid = con.conindid
    WHERE con.conrelid = 'orders'::regclass
      AND con.contype = 'u'
      AND con.conkey = ARRAY[(SELECT a.attnum FROM pg_attribute a
                              WHERE a.attrelid = 'orders'::regclass
                                AND a.attname = 'external_ref')]
      AND i.indisvalid
  ) AS have_constraint,
  coalesce((
    SELECT c.relname
    FROM pg_index i
    JOIN pg_class c     ON c.oid = i.indexrelid
    JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attname = 'external_ref'
    WHERE i.indrelid = 'orders'::regclass
      AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive AND i.indimmediate
      AND NOT i.indisprimary
      AND NOT i.indnullsnotdistinct
      AND i.indnatts = 1 AND i.indnkeyatts = 1
      AND i.indkey[0] = a.attnum
      AND i.indexprs IS NULL AND i.indpred IS NULL
      AND i.indoption[0] = 0
      AND i.indcollation[0] = a.attcollation
      AND c.relam = (SELECT oid FROM pg_am WHERE amname = 'btree')
      AND i.indclass[0] = (SELECT oc.oid FROM pg_opclass oc JOIN pg_am am ON am.oid = oc.opcmethod
                           WHERE am.amname = 'btree' AND oc.opcdefault AND oc.opcintype = 'text'::regtype)
      AND NOT EXISTS (SELECT 1 FROM pg_constraint x WHERE x.conindid = i.indexrelid)
    ORDER BY c.relname
    LIMIT 1), '') AS reuse_idx,
  CASE WHEN to_regclass(quote_ident(n.nspname) || '.orders_external_ref_key') IS NULL
       THEN 'orders_external_ref_key'
       ELSE 'orders_external_ref_key_' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS')
  END AS new_idx
FROM pg_class t
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE t.oid = 'orders'::regclass
\gset

SELECT (NOT :'have_constraint'::boolean AND :'reuse_idx' = '') AS need_build \gset

-- 2. Build a fresh unique index only if there is neither a constraint nor a reusable valid index.
\if :need_build
CREATE UNIQUE INDEX CONCURRENTLY :"new_idx" ON orders (external_ref);
\set target_idx :new_idx
\elif :have_constraint
\set target_idx ''
\else
\set target_idx :reuse_idx
\endif

SELECT set_config('migration.target_idx', :'target_idx', false);

-- 3. One short lock window: drop every invalid index on orders and, if needed,
--    attach the valid unique index as the UNIQUE constraint.
DO $$
DECLARE
  target   text := current_setting('migration.target_idx');
  nsp      oid  := (SELECT relnamespace FROM pg_class WHERE oid = 'orders'::regclass);
  cname    text;
  r        record;
  deadline constant timestamptz := clock_timestamp() + interval '40 seconds';
BEGIN
  IF target = '' AND NOT EXISTS (
       SELECT 1 FROM pg_index WHERE indrelid = 'orders'::regclass AND NOT indisvalid) THEN
    RETURN;  -- constraint already present and nothing to clean up
  END IF;

  IF target <> '' AND NOT EXISTS (
       SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
       WHERE i.indrelid = 'orders'::regclass AND c.relname = target AND i.indisvalid) THEN
    RAISE EXCEPTION 'index % is missing or not valid', target;
  END IF;

  PERFORM set_config('lock_timeout', '100ms', true);
  LOOP
    BEGIN
      FOR r IN
        SELECT i.indexrelid
        FROM pg_index i
        WHERE i.indrelid = 'orders'::regclass AND NOT i.indisvalid
      LOOP
        EXECUTE format('DROP INDEX %s', r.indexrelid::regclass);
      END LOOP;

      IF target <> '' THEN
        IF target = 'orders_external_ref_key'
           OR (NOT EXISTS (SELECT 1 FROM pg_class
                           WHERE relname = 'orders_external_ref_key' AND relnamespace = nsp)
               AND NOT EXISTS (SELECT 1 FROM pg_constraint
                               WHERE conname = 'orders_external_ref_key'
                                 AND conrelid = 'orders'::regclass)) THEN
          cname := 'orders_external_ref_key';
        ELSE
          cname := target;
        END IF;
        EXECUTE format('ALTER TABLE orders ADD CONSTRAINT %I UNIQUE USING INDEX %I', cname, target);
      END IF;
      EXIT;
    EXCEPTION WHEN lock_not_available OR deadlock_detected THEN
      IF clock_timestamp() > deadline THEN RAISE; END IF;
      PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END
$$;

-- 4. Sanity check of the end state.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_index WHERE indrelid = 'orders'::regclass AND NOT indisvalid) THEN
    RAISE EXCEPTION 'invalid index still present on orders';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint con
    JOIN pg_index i ON i.indexrelid = con.conindid
    JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attname = 'external_ref'
    WHERE con.conrelid = 'orders'::regclass AND con.contype = 'u'
      AND con.conkey = ARRAY[a.attnum] AND i.indisvalid) THEN
    RAISE EXCEPTION 'unique constraint on orders(external_ref) not present';
  END IF;
END
$$;
```
