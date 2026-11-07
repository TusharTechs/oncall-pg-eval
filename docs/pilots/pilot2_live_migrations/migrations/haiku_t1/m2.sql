-- M2: orders.customer_id NOT NULL + validated FK to customers(id)
-- SET NOT NULL alone would scan 5M rows under ACCESS EXCLUSIVE and stall the app.
-- Instead: NOT VALID CHECK -> VALIDATE (SHARE UPDATE EXCLUSIVE, does not block DML) ->
-- SET NOT NULL (PG12+ skips the scan because a validated CHECK proves it) -> drop helper CHECK.
-- The FK is added NOT VALID (catalog-only) and validated separately, without blocking DML.
SET lock_timeout = '100ms';

CREATE PROCEDURE mig_retry_ddl(stmt text)
LANGUAGE plpgsql AS $proc$
BEGIN
  FOR attempt IN 1..1000 LOOP
    BEGIN
      EXECUTE stmt;
      RETURN;
    EXCEPTION WHEN lock_not_available THEN
      PERFORM pg_sleep(0.05);
    END;
  END LOOP;
  RAISE EXCEPTION 'could not acquire lock for: %', stmt;
END
$proc$;

CALL mig_retry_ddl($q$ALTER TABLE orders ADD CONSTRAINT orders_customer_id_nn CHECK (customer_id IS NOT NULL) NOT VALID$q$);
CALL mig_retry_ddl($q$ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_nn$q$);
CALL mig_retry_ddl($q$ALTER TABLE orders ALTER COLUMN customer_id SET NOT NULL$q$);
CALL mig_retry_ddl($q$ALTER TABLE orders DROP CONSTRAINT orders_customer_id_nn$q$);

CALL mig_retry_ddl($q$ALTER TABLE orders ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID$q$);
CALL mig_retry_ddl($q$ALTER TABLE orders VALIDATE CONSTRAINT orders_customer_id_fkey$q$);

DROP PROCEDURE mig_retry_ddl(text);
