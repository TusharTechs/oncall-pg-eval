DO $$
BEGIN
  LOOP
    BEGIN
      PERFORM set_config('lock_timeout', '50ms', true);
      EXECUTE 'ALTER TABLE orders ADD COLUMN IF NOT EXISTS public_id uuid';
      EXECUTE 'ALTER TABLE orders ALTER COLUMN public_id SET DEFAULT gen_random_uuid()';
      EXIT;
    EXCEPTION
      WHEN lock_not_available THEN
        PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

SET synchronous_commit = off;
SET lock_timeout = 0;

DO $$
DECLARE
  v_batch_size bigint := 10000;
  v_cur_id bigint;
  v_max_id bigint;
BEGIN
  SELECT min(id), max(id) INTO v_cur_id, v_max_id FROM orders;
  IF v_cur_id IS NOT NULL AND v_max_id IS NOT NULL THEN
    WHILE v_cur_id <= v_max_id LOOP
      UPDATE orders
         SET public_id = gen_random_uuid()
       WHERE id >= v_cur_id
         AND id < v_cur_id + v_batch_size
         AND public_id IS NULL;
      COMMIT;
      v_cur_id := v_cur_id + v_batch_size;
    END LOOP;
  END IF;
END $$;

SET synchronous_commit = on;

DO $$
BEGIN
  LOOP
    BEGIN
      PERFORM set_config('lock_timeout', '50ms', true);
      EXECUTE 'ALTER TABLE orders ADD CONSTRAINT orders_public_id_not_null CHECK (public_id IS NOT NULL) NOT VALID';
      EXIT;
    EXCEPTION
      WHEN lock_not_available THEN
        PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;

ALTER TABLE orders VALIDATE CONSTRAINT orders_public_id_not_null;

DO $$
BEGIN
  LOOP
    BEGIN
      PERFORM set_config('lock_timeout', '50ms', true);
      EXECUTE 'ALTER TABLE orders ALTER COLUMN public_id SET NOT NULL';
      EXECUTE 'ALTER TABLE orders DROP CONSTRAINT orders_public_id_not_null';
      EXIT;
    EXCEPTION
      WHEN lock_not_available THEN
        PERFORM pg_sleep(0.1);
    END;
  END LOOP;
END $$;
