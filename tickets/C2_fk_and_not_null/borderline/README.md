Scripts here are *not* used as must-fail grader checks, because their outcome is legitimately close to the budget on
this hardware (calibration pass 1, 2026-11-07):
- `duty_cycle_hot_retry.sql`: 175 ms lock wait + 10 ms pause. Peak 425 ms on C2 (pass), 958 ms on C1 (fail). Its outcome
  depends on how the retries line up with the analytics reader. pass^k across trials captures exactly this unreliability.
- `fk_validated_inline.sql`: validating the FK while holding SHARE ROW EXCLUSIVE scans 5M rows in ~0.4 s, which is under
  the 500 ms budget here (peak 410 ms). It is unsafe on larger tables, but within this ticket's stated constraints it is acceptable.
