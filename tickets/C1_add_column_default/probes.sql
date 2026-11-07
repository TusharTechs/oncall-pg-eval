-- Runs as role app after the migration.
WITH i AS (INSERT INTO orders(customer_id, external_ref, qty, status, amount)
           VALUES (1, 'probe-' || gen_random_uuid(), 1, 'new', 12.34) RETURNING to_jsonb(orders) ->> 'region' AS region)
SELECT 'PROBE|app_insert_gets_EU|' || CASE WHEN region = 'EU' THEN 'PASS' ELSE 'FAIL' END || '|' || coalesce(region, 'NULL') FROM i;
