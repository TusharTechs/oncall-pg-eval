SELECT 'CHECK|amount_cents_bigint_not_null|' || CASE WHEN count(*) = 1 THEN 'PASS' ELSE 'FAIL' END || '|' || count(*)
  FROM pg_attribute WHERE attrelid = 'orders'::regclass AND attname = 'amount_cents' AND NOT attisdropped AND attnotnull
   AND format_type(atttypid, atttypmod) = 'bigint';
SELECT 'CHECK|all_rows_consistent|' || CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END || '|' || n || ' mismatching rows'
  FROM (SELECT count(*) n FROM orders WHERE (to_jsonb(orders) ->> 'amount_cents')::bigint IS DISTINCT FROM (amount * 100)::bigint) s;
SELECT 'CHECK|no_invalid_indexes|' || CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END || '|' || count(*)
  FROM pg_index WHERE indrelid = 'orders'::regclass AND NOT indisvalid;
