-- WRONG: "wait out" the reader once, then plain ALTER. The next reader may already be open.
SELECT pg_sleep(13);
ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU';
