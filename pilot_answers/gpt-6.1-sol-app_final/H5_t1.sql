DO $backfill$
DECLARE
    batch record;
    remaining integer;
    updated_rows integer;
BEGIN
    -- Materialize only the batch boundaries when the cursor survives the first commit.
    FOR batch IN
        SELECT min(order_id) AS first_id,
               max(order_id) AS last_id,
               count(*)::integer AS batch_count
        FROM (
            SELECT order_id,
                   (row_number() OVER (ORDER BY order_id) - 1) / 256 AS batch_number
            FROM legacy_customer_map
        ) AS numbered
        GROUP BY batch_number
        ORDER BY batch_number
    LOOP
        remaining := batch.batch_count;

        LOOP
            WITH picked AS MATERIALIZED (
                SELECT o.id, m.customer_id
                FROM legacy_customer_map AS m
                JOIN orders AS o ON o.id = m.order_id
                WHERE m.order_id BETWEEN batch.first_id AND batch.last_id
                  AND o.customer_id IS NULL
                ORDER BY m.order_id
                FOR NO KEY UPDATE OF o SKIP LOCKED
            )
            UPDATE orders AS o
            SET customer_id = picked.customer_id
            FROM picked
            WHERE o.id = picked.id;

            GET DIAGNOSTICS updated_rows = ROW_COUNT;
            remaining := remaining - updated_rows;
            COMMIT;

            EXIT WHEN remaining = 0;
            PERFORM pg_sleep(0.005);
        END LOOP;
    END LOOP;
END;
$backfill$;

DO $constraints$
DECLARE
    orders_oid constant oid := 'orders'::regclass;
    database_oid constant oid := (
        SELECT oid FROM pg_database WHERE datname = current_database()
    );
BEGIN
    FOR phase IN 1..2 LOOP
        PERFORM set_config('lock_timeout', '35ms', true);

        LOOP
            -- Wait outside the lock queue while an analytics reader holds the table.
            IF NOT EXISTS (
                SELECT 1
                FROM pg_locks
                WHERE locktype = 'relation'
                  AND database = database_oid
                  AND relation = orders_oid
                  AND mode = 'AccessShareLock'
                  AND granted
                  AND pid <> pg_backend_pid()
            ) THEN
                BEGIN
                    IF phase = 1 THEN
                        LOCK TABLE customers IN SHARE ROW EXCLUSIVE MODE NOWAIT;
                    END IF;

                    LOCK TABLE orders IN ACCESS EXCLUSIVE MODE;
                    EXIT;
                EXCEPTION
                    WHEN lock_not_available THEN
                        NULL;
                END;
            END IF;

            PERFORM pg_sleep(0.040);
        END LOOP;

        IF phase = 1 THEN
            ALTER TABLE orders
                ADD CONSTRAINT orders_customer_id_nn_check
                    CHECK (customer_id IS NOT NULL) NOT VALID,
                ADD CONSTRAINT orders_customer_id_fkey
                    FOREIGN KEY (customer_id) REFERENCES customers (id) NOT VALID;
            COMMIT;

            -- Validation uses a lock on orders that permits application writes.
            ALTER TABLE orders
                VALIDATE CONSTRAINT orders_customer_id_nn_check,
                VALIDATE CONSTRAINT orders_customer_id_fkey;
            COMMIT;
        ELSE
            -- The validated check lets PostgreSQL skip the SET NOT NULL scan.
            ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
            COMMIT;
        END IF;
    END LOOP;
END;
$constraints$;
