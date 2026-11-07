-- M1
\set ON_ERROR_STOP on

SET statement_timeout = '40s';
SET lock_timeout = '175ms';

DO $migration$
BEGIN
    LOOP
        BEGIN
            LOCK TABLE public.orders IN ACCESS EXCLUSIVE MODE;

            ALTER TABLE public.orders
                ADD COLUMN region text NOT NULL DEFAULT 'EU';

            RETURN;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        PERFORM pg_sleep(0.2);
    END LOOP;
END
$migration$;
