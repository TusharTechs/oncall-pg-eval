-- WRONG: looks like the "instant ADD COLUMN DEFAULT" of PG11+, but the default is volatile -> full rewrite under ACCESS EXCLUSIVE.
SET lock_timeout = '50ms';
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN
  ALTER TABLE orders ADD COLUMN public_id uuid NOT NULL DEFAULT gen_random_uuid(); RETURN;
  EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; END $$;
