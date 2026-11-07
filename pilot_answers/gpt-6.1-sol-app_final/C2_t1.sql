DO $migration$
DECLARE
    orders_oid oid := 'orders'::regclass;
    database_oid oid := (
        SELECT oid FROM pg_catalog.pg_database
        WHERE datname = current_database()
    );
BEGIN
    PERFORM pg_catalog.set_config('lock_timeout', '30ms', true);

    LOOP
        -- Wait outside the lock queue while an analytics reader holds the table.
        IF NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_locks
            WHERE locktype = 'relation'
              AND database = database_oid
              AND relation = orders_oid
              AND mode = 'AccessShareLock'
              AND granted
        ) THEN
            BEGIN
                ALTER TABLE orders
                    ADD CONSTRAINT orders_customer_id_nn
                        CHECK (customer_id IS NOT NULL) NOT VALID,
                    ADD CONSTRAINT orders_customer_id_fkey
                        FOREIGN KEY (customer_id) REFERENCES customers (id) NOT VALID;
                EXIT;
            EXCEPTION
                WHEN lock_not_available THEN NULL;
            END;
        END IF;

        PERFORM pg_catalog.pg_sleep(0.05);
    END LOOP;
END;
$migration$;

-- Validation permits concurrent reads and writes on orders.
ALTER TABLE orders
    VALIDATE CONSTRAINT orders_customer_id_nn,
    VALIDATE CONSTRAINT orders_customer_id_fkey;

DO $migration$
DECLARE
    orders_oid oid := 'orders'::regclass;
    database_oid oid := (
        SELECT oid FROM pg_catalog.pg_database
        WHERE datname = current_database()
    );
BEGIN
    PERFORM pg_catalog.set_config('lock_timeout', '30ms', true);

    LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_locks
            WHERE locktype = 'relation'
              AND database = database_oid
              AND relation = orders_oid
              AND mode = 'AccessShareLock'
              AND granted
        ) THEN
            BEGIN
                -- The validated check lets PostgreSQL skip the table scan.
                ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
                EXIT;
            EXCEPTION
                WHEN lock_not_available THEN NULL;
            END;
        END IF;

        PERFORM pg_catalog.pg_sleep(0.05);
    END LOOP;
END;
$migration$;
