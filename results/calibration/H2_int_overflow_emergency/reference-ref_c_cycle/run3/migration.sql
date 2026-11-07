-- Reference C (unusual but valid): let the sequence CYCLE. After the int4 maximum it wraps to MINVALUE (1), and
-- ids 1 .. ~2.145 billion are unused, so the next 1e9 inserts succeed without collisions. ALTER SEQUENCE locks only the sequence.
SET lock_timeout = '50ms';
DO $$ BEGIN
  FOR i IN 1..300 LOOP BEGIN ALTER SEQUENCE events_id_seq CYCLE; RETURN;
  EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.05); END; END LOOP;
  RAISE EXCEPTION 'could not alter sequence';
END $$;
