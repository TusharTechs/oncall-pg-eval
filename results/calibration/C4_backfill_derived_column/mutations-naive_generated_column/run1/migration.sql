-- WRONG: stored generated column = full table rewrite under ACCESS EXCLUSIVE.
ALTER TABLE orders ADD COLUMN amount_cents bigint GENERATED ALWAYS AS ((amount * 100)::bigint) STORED;
ALTER TABLE orders ALTER COLUMN amount_cents SET NOT NULL;
