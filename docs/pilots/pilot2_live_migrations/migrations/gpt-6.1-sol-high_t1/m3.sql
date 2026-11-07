-- M3
\set ON_ERROR_STOP on

-- Concurrent index creation must run outside an explicit transaction.
-- Its waits for existing transactions must not inherit a short lock timeout.
SET statement_timeout = '35s';
SET lock_timeout = '0';

CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key
    ON public.orders (external_ref);

SET statement_timeout = '8s';
SET lock_timeout = '175ms';

DO $migration$
BEGIN
    LOOP
        BEGIN
            LOCK TABLE public.orders IN ACCESS EXCLUSIVE MODE;

            ALTER TABLE public.orders
                ADD CONSTRAINT orders_external_ref_key
                UNIQUE USING INDEX orders_external_ref_key;

            RETURN;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        PERFORM pg_sleep(0.01);
    END LOOP;
END
$migration$;
