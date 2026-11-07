-- Repair in primary-key order. Commit each batch to release row locks,
-- and retry any rows that SKIP LOCKED left behind.
DO $repair$
DECLARE
    next_order_id bigint;
    last_order_id bigint;
    batch_ids bigint[];
BEGIN
    SELECT min(order_id) INTO next_order_id
    FROM legacy_customer_map;

    WHILE next_order_id IS NOT NULL LOOP
        SELECT array_agg(batch.order_id), max(batch.order_id)
        INTO batch_ids, last_order_id
        FROM (
            SELECT order_id
            FROM legacy_customer_map
            WHERE order_id >= next_order_id
            ORDER BY order_id
            LIMIT 256
        ) AS batch;

        LOOP
            -- The later synchronous DDL commit flushes the repair WAL too.
            SET LOCAL synchronous_commit = off;

            WITH locked AS MATERIALIZED (
                SELECT o.id, m.customer_id
                FROM unnest(batch_ids) AS batch(order_id)
                JOIN legacy_customer_map AS m USING (order_id)
                JOIN orders AS o ON o.id = batch.order_id
                FOR NO KEY UPDATE OF o SKIP LOCKED
            ),
            repaired AS (
                UPDATE orders AS o
                SET customer_id = locked.customer_id
                FROM locked
                WHERE o.id = locked.id
                RETURNING o.id
            )
            SELECT array_agg(batch.order_id)
            INTO batch_ids
            FROM unnest(batch_ids) AS batch(order_id)
            WHERE NOT EXISTS (
                SELECT 1 FROM repaired WHERE repaired.id = batch.order_id
            );

            COMMIT;
            EXIT WHEN batch_ids IS NULL;
            PERFORM pg_sleep(0.005);
        END LOOP;

        SELECT order_id INTO next_order_id
        FROM legacy_customer_map
        WHERE order_id > last_order_id
        ORDER BY order_id
        LIMIT 1;
    END LOOP;
END;
$repair$;

-- Bound each exclusive lock attempt so a long reader cannot leave app
-- transactions queued behind the migration for the duration of its read.
DO $install$
BEGIN
    SET LOCAL lock_timeout = '10ms';

    LOOP
        BEGIN
            LOCK TABLE orders IN ACCESS EXCLUSIVE MODE;
            LOCK TABLE customers IN SHARE ROW EXCLUSIVE MODE NOWAIT;

            ALTER TABLE orders
                ADD CONSTRAINT orders_h5_customer_id_present
                    CHECK (customer_id IS NOT NULL) NOT VALID,
                ADD CONSTRAINT orders_h5_customer_id_fkey
                    FOREIGN KEY (customer_id) REFERENCES customers (id) NOT VALID;
            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN NULL;
        END;

        PERFORM pg_sleep(0.050);
    END LOOP;
END;
$install$;

-- Validation permits concurrent reads, inserts, and updates.
ALTER TABLE orders
    VALIDATE CONSTRAINT orders_h5_customer_id_present,
    VALIDATE CONSTRAINT orders_h5_customer_id_fkey;

-- The validated CHECK lets SET NOT NULL skip the heap scan.
DO $finalize$
BEGIN
    SET LOCAL lock_timeout = '10ms';

    LOOP
        BEGIN
            LOCK TABLE orders IN ACCESS EXCLUSIVE MODE;
            ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN NULL;
        END;

        PERFORM pg_sleep(0.050);
    END LOOP;
END;
$finalize$;
