-- Run in psql's default autocommit mode.
-- NOWAIT prevents DDL lock requests from queuing behind analytics readers.

DO $migration$
BEGIN
    LOOP
        BEGIN
            LOCK TABLE public.orders IN ACCESS EXCLUSIVE MODE NOWAIT;

            ALTER TABLE public.orders ADD COLUMN public_id uuid;
            ALTER TABLE public.orders
                ALTER COLUMN public_id SET DEFAULT pg_catalog.gen_random_uuid();

            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        PERFORM pg_catalog.pg_sleep(0.01);
    END LOOP;
END
$migration$;

-- Commit small batches and skip rows currently locked by the application.
-- Revisit skipped rows before declaring the backfill complete.
--
-- Encode existing primary keys injectively in UUIDs with version bits zero.
-- These cannot overlap the version-4 UUIDs produced by gen_random_uuid().
DO $backfill$
DECLARE
    next_id bigint;
    last_id bigint;
BEGIN
    SELECT min(id) INTO next_id FROM public.orders;

    WHILE next_id IS NOT NULL LOOP
        WITH batch AS MATERIALIZED (
            SELECT o.ctid
            FROM public.orders AS o
            WHERE o.id >= next_id
              AND o.public_id IS NULL
            ORDER BY o.id
            LIMIT 1000
            FOR NO KEY UPDATE OF o SKIP LOCKED
        ),
        changed AS (
            UPDATE public.orders AS o
            SET public_id =
                pg_catalog.lpad(pg_catalog.to_hex(o.id), 32, '0')::uuid
            FROM batch AS b
            WHERE o.ctid = b.ctid
            RETURNING o.id
        )
        SELECT max(id) INTO last_id FROM changed;

        COMMIT;

        IF last_id IS NOT NULL THEN
            next_id := last_id;
        ELSE
            SELECT min(id)
            INTO next_id
            FROM public.orders
            WHERE public_id IS NULL;

            COMMIT;

            IF next_id IS NOT NULL THEN
                PERFORM pg_catalog.pg_sleep(0.005);
            END IF;
        END IF;
    END LOOP;
END
$backfill$;

-- All existing rows are populated; concurrent inserts receive the default.
DO $constraint$
BEGIN
    LOOP
        BEGIN
            LOCK TABLE public.orders IN ACCESS EXCLUSIVE MODE NOWAIT;

            ALTER TABLE public.orders
                ADD CONSTRAINT orders_public_id_nn_migration
                CHECK (public_id IS NOT NULL) NOT VALID;

            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        PERFORM pg_catalog.pg_sleep(0.01);
    END LOOP;
END
$constraint$;

-- Validation permits ordinary SELECT, INSERT, and UPDATE traffic.
ALTER TABLE public.orders
    VALIDATE CONSTRAINT orders_public_id_nn_migration;

-- A validated CHECK avoids a table scan while holding ACCESS EXCLUSIVE.
-- Drop it in a separate ALTER statement so it proves SET NOT NULL.
-- Reference: [PostgreSQL 17 ALTER TABLE](https://www.postgresql.org/docs/17/sql-altertable.html)
DO $finalize$
BEGIN
    LOOP
        BEGIN
            LOCK TABLE public.orders IN ACCESS EXCLUSIVE MODE NOWAIT;

            ALTER TABLE public.orders
                ALTER COLUMN public_id SET NOT NULL;

            ALTER TABLE public.orders
                DROP CONSTRAINT orders_public_id_nn_migration;

            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        PERFORM pg_catalog.pg_sleep(0.01);
    END LOOP;
END
$finalize$;

-- Existing table-level app privileges cover the added column.
-- No new sequences, functions, indexes, or persistent helper objects exist.
