WITH i AS (INSERT INTO events(order_id, kind) VALUES (1, 'probe') RETURNING id)
SELECT 'PROBE|app_insert_into_events_ok|PASS|id=' || id FROM i;
