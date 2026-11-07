DO $migration$
BEGIN
    -- Limit how long a queued lock request can hold up new app transactions.
    PERFORM pg_catalog.set_config('lock_timeout', '25ms', true);

    LOOP
        BEGIN
            LOCK TABLE orders IN ACCESS EXCLUSIVE MODE;
            EXIT;
        EXCEPTION
            WHEN lock_not_available THEN
                NULL;
        END;

        -- Give queued transactions time to run before trying again.
        PERFORM pg_catalog.pg_sleep(0.100);
    END LOOP;

    -- PostgreSQL supplies the constant default to existing rows without a rewrite.
    ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU';
END;
$migration$;
