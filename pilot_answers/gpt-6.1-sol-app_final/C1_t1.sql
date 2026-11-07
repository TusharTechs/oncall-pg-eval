DO $migration$
BEGIN
    LOOP
        BEGIN
            LOCK TABLE orders IN ACCESS EXCLUSIVE MODE NOWAIT;
            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        PERFORM pg_sleep(0.01);
    END LOOP;

    ALTER TABLE orders
        ADD COLUMN region text NOT NULL DEFAULT 'EU';
END;
$migration$;
