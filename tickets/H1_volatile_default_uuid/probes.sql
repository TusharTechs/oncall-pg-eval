WITH i AS (INSERT INTO orders(customer_id, external_ref, qty, status, amount) VALUES (3, 'probe-' || gen_random_uuid(), 1, 'new', 1)
           RETURNING to_jsonb(orders) ->> 'public_id' AS v)
SELECT 'PROBE|app_insert_gets_public_id|' || CASE WHEN v IS NOT NULL THEN 'PASS' ELSE 'FAIL' END || '|' || coalesce(v, 'NULL') FROM i;
