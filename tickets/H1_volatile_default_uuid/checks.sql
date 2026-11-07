SELECT 'CHECK|public_id_uuid_not_null|' || CASE WHEN count(*) = 1 THEN 'PASS' ELSE 'FAIL' END || '|' || count(*)
  FROM pg_attribute WHERE attrelid = 'orders'::regclass AND attname = 'public_id' AND NOT attisdropped AND attnotnull
   AND format_type(atttypid, atttypmod) = 'uuid';
SELECT 'CHECK|default_gen_random_uuid|' || CASE WHEN coalesce(max(pg_get_expr(d.adbin, d.adrelid)), '') = 'gen_random_uuid()' THEN 'PASS' ELSE 'FAIL' END
       || '|' || coalesce(max(pg_get_expr(d.adbin, d.adrelid)), 'none')
  FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
 WHERE d.adrelid = 'orders'::regclass AND a.attname = 'public_id';
SELECT 'CHECK|all_rows_distinct_non_null|' || CASE WHEN nulls = 0 AND dups = 0 THEN 'PASS' ELSE 'FAIL' END || '|nulls=' || nulls || ' dups=' || dups
  FROM (SELECT count(*) FILTER (WHERE v IS NULL) nulls, count(v) - count(DISTINCT v) dups
          FROM (SELECT to_jsonb(orders) ->> 'public_id' v FROM orders) s) q;
