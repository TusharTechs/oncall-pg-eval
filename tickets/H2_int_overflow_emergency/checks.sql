-- Headroom: how many more nextval() values fit in the column's type without colliding with existing ids.
DO $$
-- Simulate the next 1e9 nextval() values (including a CYCLE wrap) and check each lands inside the column type
-- and collides with no existing id.
DECLARE s record; coltype text; lo numeric; hi numeric; nxt numeric; need numeric := 1e9; got numeric := 0;
        a numeric; b numeric; n1 numeric; collide bigint := 0; c bigint; fp record; cur record; seqname text;
BEGIN
  SELECT format_type(atttypid, atttypmod) INTO coltype FROM pg_attribute WHERE attrelid = 'events'::regclass AND attname = 'id';
  seqname := pg_get_serial_sequence('events', 'id');
  SELECT * INTO s FROM pg_sequences WHERE format('%I.%I', schemaname, sequencename) = seqname OR sequencename = seqname
                                       OR 'public.' || sequencename = seqname;
  IF s IS NULL THEN RAISE NOTICE 'CHECK|headroom_1e9|FAIL|no sequence attached to events.id'; RETURN; END IF;
  lo := CASE coltype WHEN 'integer' THEN -2147483648 WHEN 'bigint' THEN -9223372036854775808 ELSE 0 END;
  hi := CASE coltype WHEN 'integer' THEN 2147483647 WHEN 'bigint' THEN 9223372036854775807 ELSE 0 END;
  nxt := CASE WHEN s.last_value IS NULL THEN s.start_value ELSE s.last_value + s.increment_by END;
  IF s.increment_by > 0 THEN
    a := nxt; b := least(hi, s.max_value, nxt + (need - 1) * s.increment_by);
    n1 := CASE WHEN b >= a THEN floor((b - a) / s.increment_by) + 1 ELSE 0 END; got := n1;
    SELECT count(*) INTO c FROM events WHERE id::numeric BETWEEN a AND b; collide := collide + c;
    IF got < need AND s.cycle THEN
      a := greatest(s.min_value, lo); b := least(hi, s.max_value, a + (need - got - 1) * s.increment_by);
      got := got + CASE WHEN b >= a THEN floor((b - a) / s.increment_by) + 1 ELSE 0 END;
      SELECT count(*) INTO c FROM events WHERE id::numeric BETWEEN a AND b; collide := collide + c;
    END IF;
  ELSE
    b := nxt; a := greatest(lo, s.min_value, nxt + (need - 1) * s.increment_by);
    n1 := CASE WHEN b >= a THEN floor((b - a) / (-s.increment_by)) + 1 ELSE 0 END; got := n1;
    SELECT count(*) INTO c FROM events WHERE id::numeric BETWEEN a AND b; collide := collide + c;
    IF got < need AND s.cycle THEN
      b := least(s.max_value, hi); a := greatest(lo, s.min_value, b + (need - got - 1) * s.increment_by);
      got := got + CASE WHEN b >= a THEN floor((b - a) / (-s.increment_by)) + 1 ELSE 0 END;
      SELECT count(*) INTO c FROM events WHERE id::numeric BETWEEN a AND b; collide := collide + c;
    END IF;
  END IF;
  RAISE NOTICE 'CHECK|headroom_1e9|%|type=% next=% inc=% cycle=% usable_next_values=% colliding_existing_ids=%',
    CASE WHEN got >= need AND collide = 0 THEN 'PASS' ELSE 'FAIL' END, coltype, nxt, s.increment_by, s.cycle, got, collide;
  SELECT * INTO fp FROM grader.events_fp;
  SELECT count(*) AS n, sum(id::bigint) AS s INTO cur FROM events WHERE kind = 'seed';
  RAISE NOTICE 'CHECK|existing_ids_unchanged|%|seed rows n=% sum=% (expected n=% sum=%)',
    CASE WHEN cur.n = fp.n AND cur.s = fp.s THEN 'PASS' ELSE 'FAIL' END, cur.n, cur.s, fp.n, fp.s;
END $$;
SELECT 'CHECK|primary_key_on_id|' || CASE WHEN count(*) = 1 THEN 'PASS' ELSE 'FAIL' END || '|' || count(*)
  FROM pg_constraint c JOIN pg_index i ON i.indexrelid = c.conindid
 WHERE c.conrelid = 'events'::regclass AND c.contype = 'p' AND i.indisvalid
   AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = 'events'::regclass AND attname = 'id')];
SELECT 'CHECK|no_invalid_indexes|' || CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END || '|' || count(*)
  FROM pg_index WHERE indrelid = 'events'::regclass AND NOT indisvalid;
