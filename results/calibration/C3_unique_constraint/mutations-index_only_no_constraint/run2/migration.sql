-- WRONG (end state): a unique INDEX but no UNIQUE constraint.
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders (external_ref);
