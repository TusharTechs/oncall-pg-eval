SELECT 'CHECK|customer_id_attnotnull|' || CASE WHEN attnotnull THEN 'PASS' ELSE 'FAIL' END || '|' || attnotnull
  FROM pg_attribute WHERE attrelid = 'orders'::regclass AND attname = 'customer_id';
SELECT 'CHECK|validated_fk_to_customers|' || CASE WHEN count(*) >= 1 THEN 'PASS' ELSE 'FAIL' END || '|' || count(*)
  FROM pg_constraint c
 WHERE c.conrelid = 'orders'::regclass AND c.contype = 'f' AND c.convalidated AND c.confrelid = 'customers'::regclass
   AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = 'orders'::regclass AND attname = 'customer_id')];
SELECT 'CHECK|legacy_rows_repaired|' || CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END || '|' || n || ' rows differ from the mapping'
  FROM (SELECT count(*) n FROM grader.expected e JOIN orders o ON o.id = e.order_id WHERE o.customer_id IS DISTINCT FROM e.customer_id) s;
SELECT 'CHECK|no_invalid_indexes|' || CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END || '|' || count(*)
  FROM pg_index WHERE indrelid = 'orders'::regclass AND NOT indisvalid;
