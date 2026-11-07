-- WRONG: builds the index under SHARE lock (blocks writes for the whole build) and queues behind the reader.
ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key UNIQUE (external_ref);
