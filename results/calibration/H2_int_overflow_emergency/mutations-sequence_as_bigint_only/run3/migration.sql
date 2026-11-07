-- WRONG (subtle): widening only the SEQUENCE; the column is still int4, so values past 2^31-1 fail with "integer out of range".
ALTER SEQUENCE events_id_seq AS bigint MAXVALUE 9223372036854775807;
