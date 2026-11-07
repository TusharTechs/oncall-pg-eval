BEGIN;
SET LOCAL lock_timeout = '20ms';
SET LOCAL statement_timeout = '15s';

DO $migration$
BEGIN
    LOOP
        BEGIN
            LOCK TABLE public.orders IN ACCESS EXCLUSIVE MODE;
            LOCK TABLE public.customers IN SHARE ROW EXCLUSIVE MODE NOWAIT;
            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN
                -- The failed attempt has released its locks before this pause.
                PERFORM pg_sleep(0.1);
        END;
    END LOOP;
END;
$migration$;

ALTER TABLE public.orders
    ADD CONSTRAINT orders_customer_id_not_null_check
        CHECK (customer_id IS NOT NULL) NOT VALID,
    ADD CONSTRAINT orders_customer_id_fkey
        FOREIGN KEY (customer_id) REFERENCES public.customers (id) NOT VALID;
COMMIT;

-- Both constraints now enforce new writes. Validate the existing rows
-- with a lock that allows application reads and writes to continue.
ALTER TABLE public.orders
    VALIDATE CONSTRAINT orders_customer_id_not_null_check,
    VALIDATE CONSTRAINT orders_customer_id_fkey;

BEGIN;
SET LOCAL lock_timeout = '20ms';
SET LOCAL statement_timeout = '15s';

DO $migration$
BEGIN
    LOOP
        BEGIN
            LOCK TABLE public.orders IN ACCESS EXCLUSIVE MODE;
            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN
                PERFORM pg_sleep(0.1);
        END;
    END LOOP;
END;
$migration$;

-- The validated check lets PostgreSQL skip the scan for SET NOT NULL.
ALTER TABLE public.orders ALTER COLUMN customer_id SET NOT NULL;
COMMIT;
