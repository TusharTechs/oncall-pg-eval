-- M4: Use a persistent trigger and committed backfill batches.
-- Timing qualification: the supplied index-build timing does not establish
-- that five million row updates will finish within 150 seconds, or that
-- every backfill transaction will release its row locks within 500 ms.
-- Those hard timing guarantees require measured backfill/commit performance;
-- PostgreSQL lock_timeout does not bound how long acquired locks are held.

SET statement_timeout = 0;
SET lock_timeout = 0;

CREATE FUNCTION public.orders_set_amount_cents()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.amount_cents := (NEW.amount * 100)::bigint;
    RETURN NEW;
END
$function$;

-- Publish the column, trigger, and new-row enforcement atomically.
-- The trigger also fills previously unprocessed rows on qty-only updates.
DO $migration$
BEGIN
    LOOP
        BEGIN
            SET LOCAL lock_timeout = '50ms';

            ALTER TABLE public.orders
                ADD COLUMN amount_cents bigint;

            CREATE TRIGGER orders_set_amount_cents
                BEFORE INSERT OR UPDATE ON public.orders
                FOR EACH ROW
                EXECUTE FUNCTION public.orders_set_amount_cents();

            ALTER TABLE public.orders
                ADD CONSTRAINT orders_amount_cents_nn
                    CHECK (amount_cents IS NOT NULL) NOT VALID;

            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        PERFORM pg_sleep(0.01);
    END LOOP;
END
$migration$;

-- This procedure intentionally has no exception block or SET clause:
-- its top-level CALL must be allowed to commit between batches.
CREATE PROCEDURE public.orders_backfill_amount_cents()
LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_next_id bigint;
    v_last_id bigint;
BEGIN
    SELECT min(id)
      INTO v_next_id
      FROM public.orders
     WHERE amount_cents IS NULL;

    COMMIT;

    WHILE v_next_id IS NOT NULL LOOP
        WITH batch AS MATERIALIZED (
            SELECT id
              FROM public.orders
             WHERE id >= v_next_id
               AND amount_cents IS NULL
             ORDER BY id
             LIMIT 256
             FOR UPDATE SKIP LOCKED
        ),
        updated AS (
            UPDATE public.orders AS o
               SET amount_cents = (o.amount * 100)::bigint
              FROM batch AS b
             WHERE o.id = b.id
            RETURNING o.id
        )
        SELECT max(id)
          INTO v_last_id
          FROM updated;

        COMMIT;

        IF v_last_id IS NOT NULL THEN
            -- Inclusive comparison also handles the maximum bigint ID.
            -- Already processed rows no longer match IS NULL.
            v_next_id := v_last_id;
        ELSE
            -- Revisit rows skipped because an application held their locks.
            -- Only a fresh search finding no NULLs establishes completion.
            SELECT min(id)
              INTO v_next_id
              FROM public.orders
             WHERE amount_cents IS NULL;

            COMMIT;

            IF v_next_id IS NOT NULL THEN
                PERFORM pg_sleep(0.01);
            END IF;
        END IF;
    END LOOP;
END
$procedure$;

CALL public.orders_backfill_amount_cents();

DROP PROCEDURE public.orders_backfill_amount_cents();

ALTER TABLE public.orders
    VALIDATE CONSTRAINT orders_amount_cents_nn;

-- Use the validated CHECK to avoid a scan under ACCESS EXCLUSIVE.
DO $migration$
BEGIN
    LOOP
        BEGIN
            SET LOCAL lock_timeout = '50ms';

            ALTER TABLE public.orders
                ALTER COLUMN amount_cents SET NOT NULL;

            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        PERFORM pg_sleep(0.01);
    END LOOP;
END
$migration$;
