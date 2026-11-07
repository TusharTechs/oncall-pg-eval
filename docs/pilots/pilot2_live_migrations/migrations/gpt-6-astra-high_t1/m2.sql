-- M2: Install enforcement without scanning under ACCESS EXCLUSIVE.
SET statement_timeout = 0;
SET lock_timeout = 0;

DO $migration$
BEGIN
    LOOP
        BEGIN
            SET LOCAL lock_timeout = '50ms';

            ALTER TABLE public.orders
                ADD CONSTRAINT orders_customer_id_nn
                    CHECK (customer_id IS NOT NULL) NOT VALID,
                ADD CONSTRAINT orders_customer_id_fkey
                    FOREIGN KEY (customer_id)
                    REFERENCES public.customers(id)
                    NOT VALID;

            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        PERFORM pg_sleep(0.01);
    END LOOP;
END
$migration$;

-- Validation permits ordinary application reads and writes.
ALTER TABLE public.orders
    VALIDATE CONSTRAINT orders_customer_id_nn,
    VALIDATE CONSTRAINT orders_customer_id_fkey;

-- The validated CHECK proves non-nullness, avoiding another table scan
-- while holding ACCESS EXCLUSIVE.
DO $migration$
BEGIN
    LOOP
        BEGIN
            SET LOCAL lock_timeout = '50ms';

            ALTER TABLE public.orders
                ALTER COLUMN customer_id SET NOT NULL;

            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        PERFORM pg_sleep(0.01);
    END LOOP;
END
$migration$;
