-- Wait for a gap in analytics reads before requesting the exclusive lock.
-- Bound the lock wait in case a reader starts between the check and the lock.
DO $migration$
DECLARE
    orders_oid CONSTANT oid := 'orders'::regclass;
    database_oid CONSTANT oid := (
        SELECT oid FROM pg_catalog.pg_database WHERE datname = current_database()
    );
    retry_until CONSTANT timestamptz := clock_timestamp() + interval '15 seconds';
BEGIN
    PERFORM set_config('lock_timeout', '25ms', true);

    LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_locks AS l
            WHERE l.locktype = 'relation'
              AND l.database = database_oid
              AND l.relation = orders_oid
              AND l.mode = 'AccessShareLock'
              AND l.granted
        ) THEN
            BEGIN
                LOCK TABLE orders IN ACCESS EXCLUSIVE MODE;
                LOCK TABLE customers IN SHARE ROW EXCLUSIVE MODE NOWAIT;

                ALTER TABLE orders
                    ADD CONSTRAINT orders_customer_id_nn
                        CHECK (customer_id IS NOT NULL) NOT VALID,
                    ADD CONSTRAINT orders_customer_id_fkey
                        FOREIGN KEY (customer_id) REFERENCES customers (id) NOT VALID;
                RETURN;
            EXCEPTION WHEN lock_not_available THEN
                -- The failed attempt releases its locks before the retry.
                NULL;
            END;
        END IF;

        IF clock_timestamp() >= retry_until THEN
            RAISE EXCEPTION 'Timed out installing customer_id constraints';
        END IF;
        PERFORM pg_sleep(0.1);
    END LOOP;
END;
$migration$;

-- Validate in a separate transaction under locks compatible with app writes.
ALTER TABLE orders
    VALIDATE CONSTRAINT orders_customer_id_nn,
    VALIDATE CONSTRAINT orders_customer_id_fkey;

-- The validated check lets SET NOT NULL skip the table scan.
DO $migration$
DECLARE
    orders_oid CONSTANT oid := 'orders'::regclass;
    database_oid CONSTANT oid := (
        SELECT oid FROM pg_catalog.pg_database WHERE datname = current_database()
    );
    retry_until CONSTANT timestamptz := clock_timestamp() + interval '15 seconds';
BEGIN
    PERFORM set_config('lock_timeout', '25ms', true);

    LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_locks AS l
            WHERE l.locktype = 'relation'
              AND l.database = database_oid
              AND l.relation = orders_oid
              AND l.mode = 'AccessShareLock'
              AND l.granted
        ) THEN
            BEGIN
                LOCK TABLE orders IN ACCESS EXCLUSIVE MODE;

                ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
                RETURN;
            EXCEPTION WHEN lock_not_available THEN
                NULL;
            END;
        END IF;

        IF clock_timestamp() >= retry_until THEN
            RAISE EXCEPTION 'Timed out setting orders.customer_id NOT NULL';
        END IF;
        PERFORM pg_sleep(0.1);
    END LOOP;
END;
$migration$;
