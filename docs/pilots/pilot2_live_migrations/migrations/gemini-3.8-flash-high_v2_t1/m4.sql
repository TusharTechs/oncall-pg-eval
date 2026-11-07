DO $$
BEGIN
  LOOP
    EXIT WHEN NOT EXISTS (
      SELECT 1
      FROM pg_locks
      WHERE relation = 'orders'::regclass
        AND mode = 'AccessShareLock'
        AND pid <> pg_backend_pid()
    );
    PERFORM pg_sleep(0.1);
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION orders_amount_cents_sync()
RETURNS trigger AS $$
BEGIN
  NEW.amount_cents := (NEW.amount * 100)::bigint;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

SET lock_timeout = '200ms';

DO $$
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD COLUMN amount_cents bigint;
      CREATE OR REPLACE TRIGGER orders_amount_cents_trg
        BEFORE INSERT OR UPDATE ON orders
        FOR EACH ROW
        EXECUTE FUNCTION orders_amount_cents_sync();
      EXIT;
    EXCEPTION
      WHEN lock_not_available THEN
        PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;

RESET lock_timeout;

DO $$
DECLARE
  v_batch_size bigint := 25000;
  v_cur_id bigint;
  v_max_id bigint;
BEGIN
  SELECT min(id), max(id) INTO v_cur_id, v_max_id FROM orders;
  IF v_cur_id IS NOT NULL THEN
    WHILE v_cur_id <= v_max_id LOOP
      UPDATE orders
      SET amount_cents = (amount * 100)::bigint
      WHERE id >= v_cur_id AND id < v_cur_id + v_batch_size
        AND amount_cents IS NULL;
      COMMIT;
      v_cur_id := v_cur_id + v_batch_size;
    END LOOP;
  END IF;
END $$;

SET lock_timeout = '200ms';

DO $$
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ADD CONSTRAINT orders_amount_cents_not_null CHECK (amount_cents IS NOT NULL) NOT VALID;
      EXIT;
    EXCEPTION
      WHEN lock_not_available THEN
        PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;

RESET lock_timeout;

ALTER TABLE orders VALIDATE CONSTRAINT orders_amount_cents_not_null;

SET lock_timeout = '200ms';

DO $$
BEGIN
  LOOP
    BEGIN
      ALTER TABLE orders ALTER COLUMN amount_cents SET NOT NULL;
      ALTER TABLE orders DROP CONSTRAINT orders_amount_cents_not_null;
      EXIT;
    EXCEPTION
      WHEN lock_not_available THEN
        PERFORM pg_sleep(0.05);
    END;
  END LOOP;
END $$;

RESET lock_timeout;
