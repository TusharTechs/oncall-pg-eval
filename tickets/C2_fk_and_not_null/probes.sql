DO $$ BEGIN
  INSERT INTO orders(customer_id, external_ref, qty, status, amount) VALUES (NULL, 'probe-' || gen_random_uuid(), 1, 'new', 1);
  RAISE NOTICE 'PROBE|null_customer_rejected|FAIL|insert with NULL customer_id succeeded';
EXCEPTION WHEN not_null_violation THEN RAISE NOTICE 'PROBE|null_customer_rejected|PASS|';
          WHEN check_violation THEN RAISE NOTICE 'PROBE|null_customer_rejected|PASS|rejected by check'; END $$;
DO $$ BEGIN
  INSERT INTO orders(customer_id, external_ref, qty, status, amount) VALUES (999999999, 'probe-' || gen_random_uuid(), 1, 'new', 1);
  RAISE NOTICE 'PROBE|unknown_customer_rejected|FAIL|insert with unknown customer_id succeeded';
EXCEPTION WHEN foreign_key_violation THEN RAISE NOTICE 'PROBE|unknown_customer_rejected|PASS|'; END $$;
WITH i AS (INSERT INTO orders(customer_id, external_ref, qty, status, amount) VALUES (42, 'probe-' || gen_random_uuid(), 1, 'new', 1) RETURNING 1)
SELECT 'PROBE|valid_insert_ok|PASS|' FROM i;
