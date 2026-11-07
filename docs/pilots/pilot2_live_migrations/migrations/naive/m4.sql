ALTER TABLE orders ADD COLUMN amount_cents bigint GENERATED ALWAYS AS ((amount * 100)::bigint) STORED;
ALTER TABLE orders ALTER COLUMN amount_cents SET NOT NULL;
