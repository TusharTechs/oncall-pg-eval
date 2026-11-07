WITH i AS (INSERT INTO orders(customer_id, external_ref, qty, status, amount) VALUES (7, 'probe-' || gen_random_uuid(), 1, 'new', 12.34)
           RETURNING (to_jsonb(orders) ->> 'amount_cents')::bigint AS c)
SELECT 'PROBE|insert_sets_amount_cents|' || CASE WHEN c = 1234 THEN 'PASS' ELSE 'FAIL' END || '|' || coalesce(c::text, 'NULL') FROM i;
WITH u AS (UPDATE orders SET amount = 55.55 WHERE id = 777 RETURNING (to_jsonb(orders) ->> 'amount_cents')::bigint AS c)
SELECT 'PROBE|update_amount_refreshes_cents|' || CASE WHEN c = 5555 THEN 'PASS' ELSE 'FAIL' END || '|' || coalesce(c::text, 'NULL') FROM u;
WITH u AS (UPDATE orders SET qty = qty + 1 WHERE id = 778 RETURNING (to_jsonb(orders) ->> 'amount_cents')::bigint AS c, (amount*100)::bigint AS want)
SELECT 'PROBE|qty_update_keeps_cents|' || CASE WHEN c = want THEN 'PASS' ELSE 'FAIL' END || '|' || coalesce(c::text, 'NULL') FROM u;
