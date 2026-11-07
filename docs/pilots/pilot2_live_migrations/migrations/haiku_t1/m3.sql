-- M3: UNIQUE (external_ref) without blocking app writes
-- CREATE INDEX CONCURRENTLY takes only SHARE UPDATE EXCLUSIVE. It must not run under
-- lock_timeout, because it legitimately waits for the open analytics transaction to finish.
-- Remove any invalid leftover from a previous failed attempt first.
SET lock_timeout = 0;
DROP INDEX CONCURRENTLY IF EXISTS orders_external_ref_uidx;
CREATE UNIQUE INDEX CONCURRENTLY orders_external_ref_uidx ON orders (external_ref);

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

-- Attaching an existing valid unique index is a brief ACCESS EXCLUSIVE operation (no scan).
SET lock_timeout = '100ms';
CALL mig_retry_ddl($q$ALTER TABLE orders ADD CONSTRAINT orders_external_ref_key UNIQUE USING INDEX orders_external_ref_uidx$q$);

DROP PROCEDURE mig_retry_ddl(text);
