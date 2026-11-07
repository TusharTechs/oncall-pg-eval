-- Preserve existing positive IDs and provide 2,147,483,648 negative IDs.
-- Altering the sequence does not require locking the events table.
ALTER SEQUENCE events_id_seq
    MINVALUE -2147483648
    RESTART WITH -2147483648
    NO CYCLE;
