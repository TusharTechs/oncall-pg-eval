-- M3: CONCURRENTLY must execute outside a transaction block.
SET statement_timeout = 0;
SET lock_timeout = 0;

CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key
    ON public.orders (external_ref);

-- Attaching the completed index requires only a brief exclusive lock.
DO $migration$
BEGIN
    LOOP
        BEGIN
            SET LOCAL lock_timeout = '50ms';

            ALTER TABLE public.orders
                ADD CONSTRAINT orders_external_ref_key
                UNIQUE USING INDEX orders_external_ref_key;

            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        PERFORM pg_sleep(0.01);
    END LOOP;
END
$migration$;
