```sql
-- M1: add region NOT NULL DEFAULT 'EU'.
-- Non-volatile constant default: metadata-only on PG11+ (no rewrite, no scan).
-- Existing rows read 'EU' via attmissingval; app INSERTs that omit region get 'EU'.
SET lock_timeout = '150ms';

CREATE FUNCTION pg_temp.retry_ddl(stmt text) RETURNS void
LANGUAGE plpgsql AS $fn$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '12 seconds';
BEGIN
  LOOP
    BEGIN
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() > deadline THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$fn$;

SELECT pg_temp.retry_ddl($d$ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU'$d$);
```

```sql
-- M2: customer_id NOT NULL + validated FK, without long ACCESS EXCLUSIVE holds
-- or full-table scans under a blocking lock.
SET lock_timeout = '150ms';

CREATE FUNCTION pg_temp.retry_ddl(stmt text) RETURNS void
LANGUAGE plpgsql AS $fn$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '12 seconds';
BEGIN
  LOOP
    BEGIN
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() > deadline THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$fn$;

-- 1. NOT VALID check: no scan, brief lock only.
SELECT pg_temp.retry_ddl($d$ALTER TABLE orders ADD CONSTRAINT orders_customer_id_nn CHECK (customer_id IS NOT NULL) NOT VALID$d$);

-- 2. Validate check: full scan under SHARE UPDATE EXCLUSIVE, does not block app DML.
SELECT pg_temp.retry_ddl($d$ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_nn$d$);

-- 3. SET NOT NULL: PG12+ uses the validated CHECK to skip the table scan.
SELECT pg_temp.retry_ddl($d$ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL$d$);

-- 4. FK added NOT VALID: no scan, brief SHARE ROW EXCLUSIVE.
SELECT pg_temp.retry_ddl($d$ALTER TABLE orders ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID$d$);

-- 5. Validate FK: SHARE UPDATE EXCLUSIVE, does not block app DML.
SELECT pg_temp.retry_ddl($d$ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey$d$);
```

```sql
-- M3: UNIQUE on orders(external_ref).
-- Build the index CONCURRENTLY (no DML blocking), then attach it as a constraint
-- (metadata-only, brief lock).
-- lock_timeout is cleared for CONCURRENTLY: its snapshot-wait phase must not time out
-- behind the analytics transaction.
SET lock_timeout = 0;

CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_key ON orders (external_ref);

SET lock_timeout = '150ms';

CREATE FUNCTION pg_temp.retry_ddl(stmt text) RETURNS void
LANGUAGE plpgsql AS $fn$
DECLARE
  deadline timestamptz := clock_timestamp() + interval '12 seconds';
BEGIN
  LOOP
    BEGIN
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      IF clock_timestamp() > deadline THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END
$fn$;

SELECT pg_temp.retry_ddl($d$ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_key$d$);
```
