SET statement_timeout = 0;
SET lock_timeout = 0;

SELECT c.oid AS table_oid,
       a.attnum AS ref_attnum,
       format('%I.%I', n.nspname, c.relname) AS table_sql
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
JOIN pg_catalog.pg_attribute AS a ON a.attrelid = c.oid
WHERE c.oid = 'orders'::regclass
  AND a.attname = 'external_ref'
  AND NOT a.attisdropped
\gset h3_

-- Concurrent drops also handle indexes left by an interrupted concurrent build.
SELECT format('DROP INDEX CONCURRENTLY %I.%I;',
              n.nspname, c.relname)
FROM pg_catalog.pg_index AS i
JOIN pg_catalog.pg_class AS c ON c.oid = i.indexrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE i.indrelid = :h3_table_oid::oid
  AND NOT i.indisvalid
ORDER BY i.indexrelid
\gexec

SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint AS c
    JOIN pg_catalog.pg_index AS i ON i.indexrelid = c.conindid
    WHERE c.conrelid = :h3_table_oid::oid
      AND c.contype = 'u'
      AND c.conkey = ARRAY[:h3_ref_attnum]::smallint[]
      AND i.indisunique
      AND i.indisvalid
      AND i.indisready
      AND i.indislive
) AS done
\gset h3_

\if :h3_done
\else

SELECT format('orders_external_ref_h3_%s',
              pg_catalog.pg_current_xact_id()) AS new_name
\gset h3_

-- Reuse a completed, unattached index from the previous attempt if possible.
WITH candidate AS (
    SELECT ic.relname
    FROM pg_catalog.pg_index AS i
    JOIN pg_catalog.pg_class AS ic ON ic.oid = i.indexrelid
    JOIN pg_catalog.pg_am AS am ON am.oid = ic.relam
    JOIN pg_catalog.pg_attribute AS a
      ON a.attrelid = i.indrelid
     AND a.attnum = :h3_ref_attnum
    JOIN pg_catalog.pg_opclass AS opc ON opc.oid = i.indclass[0]
    WHERE i.indrelid = :h3_table_oid::oid
      AND i.indisunique
      AND i.indisvalid
      AND i.indisready
      AND i.indislive
      AND i.indimmediate
      AND i.indnatts = 1
      AND i.indnkeyatts = 1
      AND i.indkey[0] = :h3_ref_attnum
      AND i.indexprs IS NULL
      AND i.indpred IS NULL
      AND am.amname = 'btree'
      AND i.indoption[0] = 0
      AND i.indcollation[0] = a.attcollation
      AND opc.opcdefault
      AND opc.opcintype = a.atttypid
      AND NOT EXISTS (
          SELECT 1
          FROM pg_catalog.pg_constraint AS c
          WHERE c.conindid = i.indexrelid
      )
    ORDER BY i.indexrelid
    LIMIT 1
)
SELECT EXISTS (SELECT 1 FROM candidate) AS have_index,
       COALESCE((SELECT relname::text FROM candidate),
                :'h3_new_name') AS index_name
\gset h3_

\if :h3_have_index
\else
CREATE UNIQUE INDEX CONCURRENTLY :"h3_index_name"
    ON :h3_table_sql (external_ref);
\endif

-- Avoid queuing an exclusive lock behind the analytics reader.
-- Bound any remaining acquisition race, releasing failed attempts completely.
SELECT format($ddl$
DO $migration$
BEGIN
    PERFORM pg_catalog.set_config('lock_timeout', '50ms', true);

    LOOP
        IF EXISTS (
            SELECT 1
            FROM pg_catalog.pg_locks AS l
            WHERE l.locktype = 'relation'
              AND l.database = (
                  SELECT d.oid
                  FROM pg_catalog.pg_database AS d
                  WHERE d.datname = pg_catalog.current_database()
              )
              AND l.relation = %s::oid
              AND l.granted
              AND l.mode = 'AccessShareLock'
              AND l.pid IS DISTINCT FROM pg_catalog.pg_backend_pid()
        ) THEN
            PERFORM pg_catalog.pg_sleep(0.05);
            CONTINUE;
        END IF;

        BEGIN
            LOCK TABLE %s IN ACCESS EXCLUSIVE MODE;

            ALTER TABLE %s
                ADD CONSTRAINT %I UNIQUE USING INDEX %I;

            RETURN;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        PERFORM pg_catalog.pg_sleep(0.10);
    END LOOP;
END;
$migration$;
$ddl$,
    :h3_table_oid,
    :'h3_table_sql',
    :'h3_table_sql',
    :'h3_new_name',
    :'h3_index_name')
\gexec

\endif
