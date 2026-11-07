-- WRONG (subtle): drops NOT NULL from the first step but keeps the volatile default -> still a full rewrite.
SET lock_timeout = '50ms';
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN
  ALTER TABLE orders ADD COLUMN public_id uuid DEFAULT gen_random_uuid(); RETURN;
  EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; END $$;
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN
  ALTER TABLE orders ADD CONSTRAINT nn CHECK (public_id IS NOT NULL) NOT VALID; RETURN;
  EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; END $$;
ALTER TABLE orders VALIDATE CONSTRAINT nn;
DO $$ BEGIN FOR i IN 1..600 LOOP BEGIN
  ALTER TABLE orders ALTER COLUMN public_id SET NOT NULL; RETURN;
  EXCEPTION WHEN lock_not_available THEN PERFORM pg_sleep(0.2); END; END LOOP; END $$;
