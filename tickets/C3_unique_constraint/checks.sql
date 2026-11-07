SELECT 'CHECK|unique_constraint_on_external_ref|' || CASE WHEN count(*) >= 1 THEN 'PASS' ELSE 'FAIL' END || '|' || count(*)
  FROM pg_constraint c JOIN pg_index i ON i.indexrelid = c.conindid
 WHERE c.conrelid = 'orders'::regclass AND c.contype = 'u' AND i.indisvalid
   AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = 'orders'::regclass AND attname = 'external_ref')];
SELECT 'CHECK|no_invalid_indexes|' || CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END || '|' || count(*)
  FROM pg_index WHERE indrelid = 'orders'::regclass AND NOT indisvalid;
