-- Existing ids are positive. Use the unused negative integer range,
-- providing 2,147,483,648 inserts before reaching zero.
-- This locks the sequence, not events, so analytics reads do not block it.
ALTER SEQUENCE events_id_seq
    MINVALUE -2147483648
    RESTART WITH -2147483648;
