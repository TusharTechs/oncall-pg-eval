```sql
-- H2: events.id identity sequence is ~5,000 values from int4 max.
-- Emergency fix: point the sequence at the unused id space below the existing ids.
-- setval only touches the sequence (no table lock, no rewrite), takes effect immediately
-- and non-transactionally, and changes no existing row. The column type change to
-- bigint is deferred to a maintenance window.
SET statement_timeout = 0;

DO $$
DECLARE
  seq    text := pg_get_serial_sequence('events', 'id');
  min_id bigint;
BEGIN
  SELECT min(id) INTO min_id FROM events;   -- PK index, instant

  IF min_id IS NULL OR min_id > 1000000001 THEN
    -- ids 1 .. min_id-1 (~2.14 billion values) are free: restart at 1.
    PERFORM setval(seq, 1, false);
  ELSE
    -- Fallback: use the negative half of the int4 range (2^31 free values).
    EXECUTE format('ALTER SEQUENCE %s MINVALUE -2147483648', seq);
    PERFORM setval(seq, -2147483648, false);
  END IF;
END $$;
```
