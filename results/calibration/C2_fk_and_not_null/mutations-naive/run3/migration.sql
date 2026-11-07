-- WRONG: validating FK + NOT NULL scan under heavy locks, queued behind the reader.
ALTER TABLE orders ADD CONSTRAINT orders_customer_fk FOREIGN KEY (customer_id) REFERENCES customers(id);
ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL;
