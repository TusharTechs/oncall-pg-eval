-- M2
\set ON_ERROR_STOP on

SET statement_timeout = '15s';
SET lock_timeout = '175ms';

DO $migration$
BEGIN
    LOOP
        BEGIN
            LOCK TABLE public.customers
                IN SHARE ROW EXCLUSIVE MODE NOWAIT;
            LOCK TABLE public.orders
                IN ACCESS EXCLUSIVE MODE;

            ALTER TABLE public.orders
                ADD CONSTRAINT orders_customer_id_nn
                    CHECK (customer_id IS NOT NULL) NOT VALID,
                ADD CONSTRAINT orders_customer_id_fkey
                    FOREIGN KEY (customer_id)
                    REFERENCES public.customers(id)
                    NOT VALID;

            RETURN;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        PERFORM pg_sleep(0.01);
    END LOOP;
END
$migration$;

SET statement_timeout = '20s';

ALTER TABLE public.orders
    VALIDATE CONSTRAINT orders_customer_id_nn,
    VALIDATE CONSTRAINT orders_customer_id_fkey;

SET statement_timeout = '8s';

DO $migration$
BEGIN
    LOOP
        BEGIN
            LOCK TABLE public.orders IN ACCESS EXCLUSIVE MODE;

            -- The validated CHECK lets PostgreSQL skip the table scan.
            ALTER TABLE public.orders
                ALTER COLUMN customer_id SET NOT NULL;

            RETURN;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        PERFORM pg_sleep(0.01);
    END LOOP;
END
$migration$;
