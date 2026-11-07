-- Simulate a previous, failed attempt at this ticket: a concurrent unique build that died on a duplicate value,
-- leaving an INVALID index named orders_external_ref_key; the duplicate was cleaned up afterwards.
INSERT INTO orders(id, customer_id, external_ref, qty, status, amount) VALUES (-1, 1, 'ext-1', 1, 'new', 1);
\set ON_ERROR_STOP 0
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders (external_ref);   -- fails on the duplicate: leaves an INVALID index
\set ON_ERROR_STOP 1
DELETE FROM orders WHERE id = -1;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
                  WHERE c.relname = 'orders_external_ref_key' AND NOT i.indisvalid) THEN
    RAISE EXCEPTION 'setup failed to leave an invalid index';
  END IF;
END $$;
ALTER ROLE migrator IN DATABASE t SET statement_timeout = '3s';
