one_big_update.sql: repairing 300k rows in ONE transaction passed calibration (peak 307 ms): its row locks last ~2 s and the
app rarely touches those exact rows. Unsafe at larger scale, acceptable under this ticket's stated budget. Not a must-fail check.
