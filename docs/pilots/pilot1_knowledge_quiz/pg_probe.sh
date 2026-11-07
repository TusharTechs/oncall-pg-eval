set -u
export PGUSER=postgres
until pg_isready -q; do sleep 0.5; done
run(){ # $1 id, $2 pre-setup sql, $3 session settings, $4 statement
psql -qAt -v ON_ERROR_STOP=0 <<SQL 2>&1 | sed "s/^/$1 /"
DROP TABLE IF EXISTS orders CASCADE; DROP TABLE IF EXISTS customers CASCADE;
CREATE TABLE customers(id bigint primary key);
INSERT INTO customers SELECT g FROM generate_series(1,1000) g;
CREATE TABLE orders(id bigint primary key, customer_id bigint, qty int, status text, amount numeric(12,2), note varchar(100), created_at timestamp);
INSERT INTO orders SELECT g, (g%1000)+1, g%7, 'new', g%500+1, 'n', now() FROM generate_series(1,200000) g;
$2
ANALYZE orders;
SELECT pg_stat_force_next_flush(); SELECT pg_sleep(0.6);
CREATE TEMP TABLE before AS SELECT pg_relation_filenode('orders') fn, (SELECT seq_scan FROM pg_stat_user_tables WHERE relname='orders') ss;
$3
BEGIN;
$4;
SELECT 'locks=' || string_agg(DISTINCT relation::regclass::text || ':' || mode, ',' ORDER BY relation::regclass::text || ':' || mode) FROM pg_locks WHERE pid=pg_backend_pid() AND relation IN ('orders'::regclass,'customers'::regclass);
COMMIT;
SELECT pg_stat_force_next_flush(); SELECT pg_sleep(0.6);
SELECT 'rewrite=' || (pg_relation_filenode('orders') <> fn) || ' seqscan_delta=' || ((SELECT seq_scan FROM pg_stat_user_tables WHERE relname='orders') - ss) FROM before;
SQL
}
run S01 "" "" "ALTER TABLE orders ADD COLUMN region text DEFAULT 'EU'"
run S02 "" "" "ALTER TABLE orders ADD COLUMN token uuid DEFAULT gen_random_uuid()"
run S03 "" "" "ALTER TABLE orders ALTER COLUMN note TYPE varchar(200)"
run S04 "" "" "ALTER TABLE orders ALTER COLUMN note TYPE varchar(50)"
run S05 "" "" "ALTER TABLE orders ALTER COLUMN amount TYPE numeric(14,2)"
run S06 "" "" "ALTER TABLE orders ALTER COLUMN amount TYPE numeric(12,4)"
run S07 "" "SET TimeZone='UTC';" "ALTER TABLE orders ALTER COLUMN created_at TYPE timestamptz"
run S08 "" "SET TimeZone='America/New_York';" "ALTER TABLE orders ALTER COLUMN created_at TYPE timestamptz"
run S09 "" "" "ALTER TABLE orders ADD CONSTRAINT amt_pos CHECK (amount > 0) NOT VALID"
run S10 "ALTER TABLE orders ADD CONSTRAINT amt_pos CHECK (amount > 0) NOT VALID;" "" "ALTER TABLE orders VALIDATE CONSTRAINT amt_pos"
run S11 "ALTER TABLE orders ADD CONSTRAINT st_nn CHECK (status IS NOT NULL);" "" "ALTER TABLE orders ALTER COLUMN status SET NOT NULL"
run S12 "" "" "ALTER TABLE orders ALTER COLUMN status SET NOT NULL"
run S13 "" "" "ALTER TABLE orders ADD CONSTRAINT fk_c FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID"
run S14 "" "" "ALTER TABLE orders ALTER COLUMN qty TYPE bigint"
run S15 "" "" "ALTER TABLE orders ALTER COLUMN note TYPE text"
run S16 "" "" "CREATE INDEX orders_status_idx ON orders(status)"
run S17 "" "" "ALTER TABLE orders ADD COLUMN ts timestamptz DEFAULT now()"
run S18 "" "" "ALTER TABLE orders ADD COLUMN flag boolean NOT NULL DEFAULT false"
run S19 "" "" "ALTER TABLE orders ADD COLUMN seq bigserial"
run S20 "" "" "CREATE INDEX CONCURRENTLY orders_note_idx ON orders(note)"
