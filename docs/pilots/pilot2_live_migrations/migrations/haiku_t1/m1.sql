-- M1: orders.region text NOT NULL DEFAULT 'EU'
-- PG11+ stores a constant non-volatile default as metadata only (no rewrite, no scan).
-- The only real cost is the ACCESS EXCLUSIVE lock, taken with a short lock_timeout and retried
-- so application transactions are never queued behind it for long.
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

CALL mig_retry_ddl($q$ALTER TABLE orders ADD COLUMN region text NOT NULL DEFAULT 'EU'$q$);

DROP PROCEDURE mig_retry_ddl(text);
