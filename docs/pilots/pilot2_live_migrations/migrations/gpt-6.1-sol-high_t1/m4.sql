-- M4
\set ON_ERROR_STOP on

SET statement_timeout = '15s';
SET lock_timeout = '175ms';

CREATE FUNCTION public.orders_set_amount_cents()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
    NEW.amount_cents := (NEW.amount * 100)::bigint;
    RETURN NEW;
END
$function$;

-- Install the column, write maintenance, and enforcement atomically.
DO $migration$
BEGIN
    LOOP
        BEGIN
            LOCK TABLE public.orders IN ACCESS EXCLUSIVE MODE;

            ALTER TABLE public.orders
                ADD COLUMN amount_cents bigint,
                ADD CONSTRAINT orders_amount_cents_nn
                    CHECK (amount_cents IS NOT NULL) NOT VALID;

            CREATE TRIGGER orders_set_amount_cents
                BEFORE INSERT OR UPDATE ON public.orders
                FOR EACH ROW
                EXECUTE FUNCTION public.orders_set_amount_cents();

            RETURN;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        PERFORM pg_sleep(0.01);
    END LOOP;
END
$migration$;

-- Rows inserted after installation are already maintained by the trigger.
CREATE TEMP TABLE orders_amount_cents_progress
ON COMMIT PRESERVE ROWS
AS
SELECT
    NULL::bigint AS last_id,
    max(id) AS upper_id,
    false AS done
FROM public.orders;

CREATE FUNCTION pg_temp.backfill_orders_amount_cents()
RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_after bigint;
    v_upper bigint;
    v_done boolean;
    v_ids bigint[];
    v_last bigint;
BEGIN
    SELECT last_id, upper_id, done
      INTO v_after, v_upper, v_done
      FROM pg_temp.orders_amount_cents_progress;

    IF v_done THEN
        RETURN;
    END IF;

    IF v_after IS NULL THEN
        SELECT array_agg(b.id), max(b.id)
          INTO v_ids, v_last
          FROM (
              SELECT id
                FROM public.orders
               WHERE id <= v_upper
               ORDER BY id
               LIMIT 1000
               FOR UPDATE NOWAIT
          ) AS b;
    ELSE
        SELECT array_agg(b.id), max(b.id)
          INTO v_ids, v_last
          FROM (
              SELECT id
                FROM public.orders
               WHERE id > v_after
                 AND id <= v_upper
               ORDER BY id
               LIMIT 1000
               FOR UPDATE NOWAIT
          ) AS b;
    END IF;

    IF v_ids IS NULL THEN
        UPDATE pg_temp.orders_amount_cents_progress
           SET done = true;
        RETURN;
    END IF;

    UPDATE public.orders
       SET amount_cents = (amount * 100)::bigint
     WHERE id = ANY (v_ids)
       AND amount_cents IS NULL;

    UPDATE pg_temp.orders_amount_cents_progress
       SET last_id = v_last,
           done = (v_last = v_upper);

EXCEPTION
    WHEN lock_not_available OR deadlock_detected OR query_canceled THEN
        -- The exception rolls back this entire batch, including its cursor
        -- advancement, and releases its row locks before returning.
        RETURN;
END
$function$;

-- Each watch execution is a separate autocommitted statement.
-- Bound each batch's execution and retry canceled/conflicting batches.
SET statement_timeout = '100ms';

\o /dev/null
SELECT pg_temp.backfill_orders_amount_cents()
WHERE NOT (SELECT done FROM pg_temp.orders_amount_cents_progress)
\watch i=0.001 m=1
\o

SET statement_timeout = '25s';

ALTER TABLE public.orders
    VALIDATE CONSTRAINT orders_amount_cents_nn;

SET statement_timeout = '8s';

DO $migration$
BEGIN
    LOOP
        BEGIN
            LOCK TABLE public.orders IN ACCESS EXCLUSIVE MODE;

            -- The validated CHECK avoids a scan under ACCESS EXCLUSIVE.
            ALTER TABLE public.orders
                ALTER COLUMN amount_cents SET NOT NULL;

            RETURN;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        PERFORM pg_sleep(0.01);
    END LOOP;
END
$migration$;
