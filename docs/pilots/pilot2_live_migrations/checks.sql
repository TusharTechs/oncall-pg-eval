\pset tuples_only on
\pset format unaligned
SELECT 'M1 ' || (
  EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='orders'::regclass AND attname='region' AND attnotnull AND NOT attisdropped
          AND format_type(atttypid, atttypmod)='text')
  AND (SELECT pg_get_expr(adbin, adrelid) FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum
       WHERE d.adrelid='orders'::regclass AND a.attname='region') = '''EU''::text'
  AND NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='orders'::regclass AND attname='region' AND NOT attisdropped) IS FALSE
) WHERE EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='orders'::regclass AND attname='region' AND NOT attisdropped);
SELECT 'M1data ' || (SELECT count(*) FROM orders WHERE region IS DISTINCT FROM 'EU') WHERE EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='orders'::regclass AND attname='region' AND NOT attisdropped);
SELECT 'M2 ' || (
  (SELECT attnotnull FROM pg_attribute WHERE attrelid='orders'::regclass AND attname='customer_id')
  AND EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid='orders'::regclass AND c.contype='f' AND c.convalidated
              AND c.confrelid='customers'::regclass
              AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid='orders'::regclass AND attname='customer_id')]
              AND c.confkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid='customers'::regclass AND attname='id')]));
SELECT 'M3 ' || EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_index i ON i.indexrelid=c.conindid
              WHERE c.conrelid='orders'::regclass AND c.contype='u' AND i.indisvalid
              AND c.conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid='orders'::regclass AND attname='external_ref')]);
SELECT 'invalid_indexes ' || count(*) FROM pg_index WHERE indrelid='orders'::regclass AND NOT indisvalid;
SELECT 'rows ' || count(*) FROM orders;
SELECT 'M4 ' || (
  (SELECT attnotnull FROM pg_attribute WHERE attrelid='orders'::regclass AND attname='amount_cents' AND NOT attisdropped)
  AND (SELECT format_type(atttypid, atttypmod) FROM pg_attribute WHERE attrelid='orders'::regclass AND attname='amount_cents') = 'bigint')
  WHERE EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='orders'::regclass AND attname='amount_cents' AND NOT attisdropped);
SELECT 'M4data_bad ' || count(*) FROM orders WHERE amount_cents IS DISTINCT FROM (amount * 100)::bigint
  AND EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='orders'::regclass AND attname='amount_cents' AND NOT attisdropped);
