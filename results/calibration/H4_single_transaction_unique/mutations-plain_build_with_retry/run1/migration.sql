-- WRONG: completes, but the index build inside the transaction blocks app writes for seconds.
SET LOCAL lock_timeout = '50ms';
ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key UNIQUE (external_ref);
