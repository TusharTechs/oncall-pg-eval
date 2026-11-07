```sql
-- H3: UNIQUE constraint on orders(external_ref), resuming from an unknown,
-- partially-failed previous attempt. Idempotent:
--   0. Override the role's statement_timeout=3s for this session (CIC needs longer).
--   1. Drop EVERY invalid index on orders (leftovers of a failed CREATE INDEX
--      CONCURRENTLY / REINDEX CONCURRENTLY), concurrently, via \gexec.
--   2. If the constraint already exists, stop. Otherwise make sure a valid unique
--      btree index on exactly (external_ref) named orders_external_ref_key exists
--      (replace an unsuitable one with that name, build it CONCURRENTLY if missing).
--   3. Attach it with ADD CONSTRAINT ... USING INDEX under a short lock_timeout,
--      retried, so we never queue behind the analytics txn (which would stall the app).
--   4. Verify the end state.

SET statement_timeout = 0;
-- CIC / DROP INDEX CONCURRENTLY wait for old transactions (analytics) through lock
-- waits; they only hold SHARE UPDATE EXCLUSIVE, which blocks neither app nor analytics.
SET lock_timeout = 0;

-- 1. Remove all invalid indexes on orders
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
       AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute
                              WHERE attrelid = 'orders'::regclass
                                AND attname = 'external_ref')]::int2[]
  ) AS has_con,
  EXISTS (
    SELECT 1
      FROM pg_index i
      JOIN pg_class ic ON ic.oid = i.indexrelid
      JOIN pg_am am    ON am.oid = ic.relam
     WHERE i.indexrelid = to_regclass('orders_external_ref_key')
       AND i.indrelid = 'orders'::regclass
       AND i.indisunique AND i.indisvalid AND i.indisready
       AND am.amname = 'btree'
       AND i.indnatts = 1 AND i.indnkeyatts = 1
       AND i.indkey[0] = (SELECT attnum FROM pg_attribute
                           WHERE attrelid = 'orders'::regclass
                             AND attname = 'external_ref')
       AND i.indpred IS NULL AND i.indexprs IS NULL
  ) AS idx_ok,
  EXISTS (
    SELECT 1 FROM pg_index i
     WHERE i.indexrelid = to_regclass('orders_external_ref_key')
       AND i.indrelid = 'orders'::regclass
  ) AS name_taken
\gset

\if :has_con
  \echo 'UNIQUE constraint on orders(external_ref) already exists; nothing to build.'
\else
  \if :idx_ok
    \echo 'Reusing existing valid unique index orders_external_ref_key.'
  \else
    \if :name_taken
      -- An unsuitable (but valid) index occupies the name: replace it.
      DROP INDEX CONCURRENTLY IF EXISTS orders_external_ref_key;
    \endif
    CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders (external_ref);
  \endif

  -- 3. Attach as constraint: momentary ACCESS EXCLUSIVE, short timeout + retry
  SET lock_timeout = '100ms';
  DO $$
  DECLARE
    deadline timestamptz := clock_timestamp() + interval '40 seconds';
  BEGIN
    LOOP
      IF EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid = 'orders'::regclass
                    AND conname = 'orders_external_ref_key') THEN
        RETURN;
      END IF;
      BEGIN
        ALTER TABLE orders
          ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key;
        RETURN;
      EXCEPTION WHEN lock_not_available THEN
        IF clock_timestamp() > deadline THEN RAISE; END IF;
        PERFORM pg_sleep(0.05);
      END;
    END LOOP;
  END
  $$;
  SET lock_timeout = 0;
\endif

-- Safety: drop any invalid index that might still exist (should be none).
SELECT format('DROP INDEX CONCURRENTLY IF EXISTS %s', i.indexrelid::regclass)
  FROM pg_index i
 WHERE i.indrelid = 'orders'::regclass
   AND NOT i.indisvalid
\gexec

-- 4. Verify end state
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
      JOIN pg_index i ON i.indexrelid = c.conindid
     WHERE c.conrelid = 'orders'::regclass
       AND c.contype = 'u'
       AND i.indisvalid
       AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute
                              WHERE attrelid = 'orders'::regclass
                                AND attname = 'external_ref')]::int2[]) THEN
    RAISE EXCEPTION 'UNIQUE constraint on orders(external_ref) missing or invalid';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_index
              WHERE indrelid = 'orders'::regclass AND NOT indisvalid) THEN
    RAISE EXCEPTION 'invalid index remains on orders';
  END IF;
END
$$;

RESET lock_timeout;
```
