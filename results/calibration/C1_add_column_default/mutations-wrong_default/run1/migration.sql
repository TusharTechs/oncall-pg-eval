-- WRONG: safe locking, but the column ends up nullable with no default (end-state + probe must fail).
SET lock_timeout = '50ms';
DO $$ BEGIN FOR i IN 1..400 LOOP BEGIN ALTER TABLE orders ADD COLUMN region text; RETURN;
  EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; END $$;
