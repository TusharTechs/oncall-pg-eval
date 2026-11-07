-- A past import bug left 300,000 orders with customer_id NULL; the correct values are in legacy_customer_map.
SET ROLE migrator;
CREATE TABLE legacy_customer_map(order_id bigint PRIMARY KEY, customer_id bigint NOT NULL);
INSERT INTO legacy_customer_map SELECT id, customer_id FROM orders WHERE id % 16 = 0 AND id <= 4800000;
UPDATE orders SET customer_id = NULL WHERE id % 16 = 0 AND id <= 4800000;
GRANT SELECT ON legacy_customer_map TO analytics;
RESET ROLE;
VACUUM ANALYZE orders; ANALYZE legacy_customer_map;
CREATE SCHEMA grader AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA grader FROM PUBLIC;
CREATE TABLE grader.expected AS SELECT order_id, customer_id FROM legacy_customer_map;
CREATE UNIQUE INDEX ON grader.expected(order_id);
