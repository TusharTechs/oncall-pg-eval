-- WRONG: waits in the lock queue behind the analytics reader; every app write queues behind it.
ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU';
