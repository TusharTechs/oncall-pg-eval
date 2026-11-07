-- M1: The constant default uses PostgreSQL's fast ADD COLUMN path.
-- Each failed lock attempt releases its locks before retrying.
SET statement_timeout = 0;
SET lock_timeout = 0;

DO $migration$
BEGIN
    LOOP
        BEGIN
            SET LOCAL lock_timeout = '50ms';

            ALTER TABLE public.orders
                ADD COLUMN region text NOT NULL DEFAULT 'EU';

            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        PERFORM pg_sleep(0.01);
    END LOOP;
END
$migration$;
