DO $migration$
DECLARE
    retry_deadline CONSTANT timestamptz := clock_timestamp() + interval '40 seconds';
BEGIN
    SET LOCAL lock_timeout = '50ms';

    LOOP
        BEGIN
            LOCK TABLE orders IN ACCESS EXCLUSIVE MODE;

            -- The constant, non-null default lets PostgreSQL skip the table rewrite and scan.
            ALTER TABLE orders
                ADD COLUMN region text NOT NULL DEFAULT 'EU';

            RETURN;
        EXCEPTION
            WHEN lock_not_available THEN
                IF clock_timestamp() >= retry_deadline THEN
                    RAISE;
                END IF;
        END;

        -- Let queued application work proceed before trying again.
        PERFORM pg_sleep(0.100);
    END LOOP;
END;
$migration$;
