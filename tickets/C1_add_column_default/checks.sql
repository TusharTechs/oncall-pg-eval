SELECT 'CHECK|column_exists_not_null_text|' || CASE WHEN count(*) = 1 THEN 'PASS' ELSE 'FAIL' END || '|' || count(*)
  FROM pg_attribute WHERE attrelid = 'orders'::regclass AND attname = 'region' AND NOT attisdropped AND attnotnull
   AND format_type(atttypid, atttypmod) = 'text';
SELECT 'CHECK|default_is_EU|' || CASE WHEN coalesce(max(pg_get_expr(d.adbin, d.adrelid)), '') = '''EU''::text' THEN 'PASS' ELSE 'FAIL' END
       || '|' || coalesce(max(pg_get_expr(d.adbin, d.adrelid)), 'none')
  FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
 WHERE d.adrelid = 'orders'::regclass AND a.attname = 'region';
SELECT 'CHECK|all_rows_EU|' || CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END || '|' || n || ' rows not EU'
  FROM (SELECT count(*) n FROM orders WHERE to_jsonb(orders) ->> 'region' IS DISTINCT FROM 'EU') s;
SELECT 'CHECK|no_invalid_indexes|' || CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END || '|' || count(*)
  FROM pg_index WHERE indrelid = 'orders'::regclass AND NOT indisvalid;
