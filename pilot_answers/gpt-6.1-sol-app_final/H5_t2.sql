-- Repair the mapped rows in small transactions to limit row lock duration.
DO $repair$
DECLARE
    batch_start bigint;
    batch_end bigint;
BEGIN
    SELECT min(order_id)
      INTO batch_start
      FROM public.legacy_customer_map;

    WHILE batch_start IS NOT NULL LOOP
        PERFORM set_config('lock_timeout', '10ms', true);

        -- The final schema change's synchronous commit flushes the repair WAL.
        PERFORM set_config('synchronous_commit', 'off', true);

        BEGIN
            WITH batch AS MATERIALIZED (
                SELECT order_id, customer_id
                  FROM public.legacy_customer_map
                 WHERE order_id >= batch_start
                 ORDER BY order_id
                 LIMIT 256
            ), repaired AS (
                UPDATE public.orders AS o
                   SET customer_id = b.customer_id
                  FROM batch AS b
                 WHERE o.id = b.order_id
                   AND o.customer_id IS DISTINCT FROM b.customer_id
            )
            SELECT max(order_id) INTO batch_end FROM batch;
        EXCEPTION
            WHEN lock_not_available THEN
                -- The failed batch's locks have been released.
                PERFORM pg_sleep(0.010);
                CONTINUE;
        END;

        COMMIT;

        -- Reuse the last key as the next lower bound. Its row is already correct.
        EXIT WHEN batch_end IS NULL OR batch_end = batch_start;
        batch_start := batch_end;
    END LOOP;
END
$repair$;

-- Bound each lock wait so a long analytics read cannot leave writers queued.
DO $install$
BEGIN
    PERFORM set_config('lock_timeout', '25ms', true);

    LOOP
        BEGIN
            ALTER TABLE public.orders
                ADD CONSTRAINT orders_customer_id_present
                    CHECK (customer_id IS NOT NULL) NOT VALID,
                ADD CONSTRAINT orders_customer_id_fkey
                    FOREIGN KEY (customer_id)
                    REFERENCES public.customers (id) NOT VALID;
            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN
                PERFORM pg_sleep(0.050);
        END;
    END LOOP;
END
$install$;

-- Validation permits concurrent reads and writes.
ALTER TABLE public.orders
    VALIDATE CONSTRAINT orders_customer_id_present,
    VALIDATE CONSTRAINT orders_customer_id_fkey;

-- The validated check lets SET NOT NULL skip the table scan.
DO $enforce$
BEGIN
    PERFORM set_config('lock_timeout', '25ms', true);

    LOOP
        BEGIN
            ALTER TABLE public.orders
                ALTER COLUMN customer_id SET NOT NULL;
            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN
                PERFORM pg_sleep(0.050);
        END;
    END LOOP;
END
$enforce$;
