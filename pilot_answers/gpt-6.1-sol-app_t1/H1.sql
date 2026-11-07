DO $migration$
BEGIN
    PERFORM pg_catalog.set_config('lock_timeout', '50ms', true);

    LOOP
        BEGIN
            LOCK TABLE public.orders IN ACCESS EXCLUSIVE MODE;

            ALTER TABLE public.orders
                ADD COLUMN public_id uuid;

            ALTER TABLE public.orders
                ALTER COLUMN public_id
                SET DEFAULT pg_catalog.gen_random_uuid();

            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN
                PERFORM pg_catalog.pg_sleep(0.05);
        END;
    END LOOP;
END
$migration$;

CREATE TEMP TABLE h1_pending_public_ids (
    id bigint
) ON COMMIT PRESERVE ROWS;

-- Commit each small batch. Skip application-held row locks and remember
-- those rows for subsequent batches.
DO $backfill$
DECLARE
    first_id bigint;
    last_id bigint;
    batch_end bigint;
    completed integer;
BEGIN
    SELECT min(id), max(id)
      INTO first_id, last_id
      FROM public.orders;

    WHILE first_id <= last_id LOOP
        batch_end := LEAST(first_id + 999, last_id);

        WITH picked AS MATERIALIZED (
            SELECT o.id
              FROM public.orders AS o
             WHERE o.id BETWEEN first_id AND batch_end
               AND o.public_id IS NULL
             ORDER BY o.id
             FOR UPDATE OF o SKIP LOCKED
        )
        UPDATE public.orders AS o
           SET public_id = pg_catalog.gen_random_uuid()
          FROM picked AS p
         WHERE o.id = p.id;

        INSERT INTO pg_temp.h1_pending_public_ids (id)
        SELECT o.id
          FROM public.orders AS o
         WHERE o.id BETWEEN first_id AND batch_end
           AND o.public_id IS NULL;

        COMMIT;
        first_id := batch_end + 1;
    END LOOP;

    LOOP
        WITH picked AS MATERIALIZED (
            SELECT o.id
              FROM public.orders AS o
              JOIN pg_temp.h1_pending_public_ids AS p
                ON p.id = o.id
             ORDER BY o.id
             LIMIT 1000
             FOR UPDATE OF o SKIP LOCKED
        ),
        changed AS (
            UPDATE public.orders AS o
               SET public_id = pg_catalog.gen_random_uuid()
              FROM picked AS p
             WHERE o.id = p.id
            RETURNING o.id
        )
        DELETE FROM pg_temp.h1_pending_public_ids AS p
         USING changed AS c
         WHERE p.id = c.id;

        GET DIAGNOSTICS completed = ROW_COUNT;
        COMMIT;

        EXIT WHEN NOT EXISTS (
            SELECT 1 FROM pg_temp.h1_pending_public_ids
        );

        IF completed = 0 THEN
            PERFORM pg_catalog.pg_sleep(0.01);
        END IF;
    END LOOP;
END
$backfill$;

DROP TABLE pg_temp.h1_pending_public_ids;

DO $add_check$
BEGIN
    PERFORM pg_catalog.set_config('lock_timeout', '50ms', true);

    LOOP
        BEGIN
            LOCK TABLE public.orders IN ACCESS EXCLUSIVE MODE;

            ALTER TABLE public.orders
                ADD CONSTRAINT orders_public_id_h1_nn
                CHECK (public_id IS NOT NULL) NOT VALID;

            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN
                PERFORM pg_catalog.pg_sleep(0.05);
        END;
    END LOOP;
END
$add_check$;

-- Validation permits concurrent application reads and writes.
ALTER TABLE public.orders
    VALIDATE CONSTRAINT orders_public_id_h1_nn;

-- The validated CHECK lets SET NOT NULL avoid a table scan while
-- holding ACCESS EXCLUSIVE.
DO $finish$
BEGIN
    PERFORM pg_catalog.set_config('lock_timeout', '50ms', true);

    LOOP
        BEGIN
            LOCK TABLE public.orders IN ACCESS EXCLUSIVE MODE;

            ALTER TABLE public.orders
                ALTER COLUMN public_id SET NOT NULL;

            ALTER TABLE public.orders
                DROP CONSTRAINT orders_public_id_h1_nn;

            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN
                PERFORM pg_catalog.pg_sleep(0.05);
        END;
    END LOOP;
END
$finish$;
