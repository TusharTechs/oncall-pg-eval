\set ON_ERROR_STOP on

-- Session settings only. Concurrent index operations must be allowed to
-- wait for existing transactions, including the analytics reader.
SET statement_timeout = 0;
SET lock_timeout = 0;

-- An interrupted concurrent build or drop can leave an invalid index.
-- Execute each concurrent drop as its own autocommit statement.
SELECT format(
           'DROP INDEX CONCURRENTLY %I.%I;',
           ns.nspname, ix.relname
       )
FROM pg_index AS i
JOIN pg_class AS ix ON ix.oid = i.indexrelid
JOIN pg_namespace AS ns ON ns.oid = ix.relnamespace
WHERE i.indrelid = 'orders'::regclass
  AND NOT i.indisvalid
ORDER BY i.indexrelid
\gexec

CREATE TEMP TABLE h3_migration_state AS
SELECT
    tbl.oid AS table_oid,
    ns.nspname AS table_schema,
    tbl.relname AS table_name,
    a.attnum,
    a.attcollation,
    ('orders_external_ref_u_' ||
        replace(gen_random_uuid()::text, '-', ''))::name AS constraint_name,
    NULL::name AS index_name,
    false AS needs_build,
    EXISTS (
        SELECT 1
        FROM pg_constraint AS con
        JOIN pg_index AS i ON i.indexrelid = con.conindid
        WHERE con.conrelid = tbl.oid
          AND con.contype = 'u'
          AND con.conkey = ARRAY[a.attnum]::smallint[]
          AND i.indisvalid
          AND i.indisready
          AND i.indislive
    ) AS already_done
FROM pg_class AS tbl
JOIN pg_namespace AS ns ON ns.oid = tbl.relnamespace
JOIN pg_attribute AS a
  ON a.attrelid = tbl.oid
 AND a.attname = 'external_ref'
 AND NOT a.attisdropped
WHERE tbl.oid = 'orders'::regclass;

-- Reuse a completed, unattached index when the previous attempt got
-- through the concurrent build. Restrict reuse to attachable indexes.
UPDATE h3_migration_state AS s
SET index_name = (
    SELECT ix.relname
    FROM pg_index AS i
    JOIN pg_class AS ix ON ix.oid = i.indexrelid
    JOIN pg_am AS am ON am.oid = ix.relam
    JOIN pg_opclass AS opc ON opc.oid = i.indclass[0]
    WHERE i.indrelid = s.table_oid
      AND i.indisunique
      AND i.indimmediate
      AND i.indisvalid
      AND i.indisready
      AND i.indislive
      AND i.indnatts = 1
      AND i.indnkeyatts = 1
      AND i.indkey[0] = s.attnum
      AND i.indexprs IS NULL
      AND i.indpred IS NULL
      AND am.amname = 'btree'
      AND i.indoption[0] = 0
      AND i.indcollation[0] = s.attcollation
      AND opc.opcdefault
      AND opc.opcintype = 'text'::regtype
      AND NOT EXISTS (
          SELECT 1
          FROM pg_constraint AS con
          WHERE con.conindid = i.indexrelid
      )
    ORDER BY i.indexrelid
    LIMIT 1
)
WHERE NOT s.already_done;

UPDATE h3_migration_state
SET index_name = constraint_name,
    needs_build = true
WHERE NOT already_done
  AND index_name IS NULL;

SELECT format(
           'CREATE UNIQUE INDEX CONCURRENTLY %I ON %I.%I (external_ref);',
           index_name, table_schema, table_name
       )
FROM h3_migration_state
WHERE needs_build
\gexec

-- Never queue an ACCESS EXCLUSIVE request behind analytics: that would
-- also queue application writes. Failed NOWAIT attempts roll back their
-- subtransaction before sleeping. A successful attempt performs only
-- the catalog attachment and releases the lock when this DO commits.
DO $migration$
DECLARE
    s record;
BEGIN
    SELECT * INTO STRICT s FROM h3_migration_state;

    IF s.already_done THEN
        RETURN;
    END IF;

    LOOP
        BEGIN
            EXECUTE format(
                'LOCK TABLE %I.%I IN ACCESS EXCLUSIVE MODE NOWAIT',
                s.table_schema, s.table_name
            );

            EXECUTE format(
                'ALTER TABLE %I.%I ADD CONSTRAINT %I UNIQUE USING INDEX %I',
                s.table_schema, s.table_name,
                s.constraint_name, s.index_name
            );

            RETURN;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        PERFORM pg_sleep(0.005);
    END LOOP;
END
$migration$;

DROP TABLE h3_migration_state;
