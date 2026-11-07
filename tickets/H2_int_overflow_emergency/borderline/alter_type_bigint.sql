-- WRONG: the textbook "fix" -- rewrite the table and rebuild the PK under ACCESS EXCLUSIVE (seconds of blocked inserts).
SET lock_timeout = '50ms';
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN
  ALTER TABLE events ALTER COLUMN id TYPE bigint; RETURN;
  EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; END $$;
ALTER SEQUENCE events_id_seq AS bigint MAXVALUE 9223372036854775807;
