DO $$ BEGIN
  INSERT INTO orders(customer_id, external_ref, qty, status, amount) VALUES (1, 'ext-12345', 1, 'new', 1);
  RAISE NOTICE 'PROBE|duplicate_external_ref_rejected|FAIL|duplicate insert succeeded';
EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'PROBE|duplicate_external_ref_rejected|PASS|'; END $$;
WITH i AS (INSERT INTO orders(customer_id, external_ref, qty, status, amount) VALUES (1, 'probe-' || gen_random_uuid(), 1, 'new', 1) RETURNING 1)
SELECT 'PROBE|valid_insert_ok|PASS|' FROM i;
