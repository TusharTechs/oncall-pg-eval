alter_type_bigint.sql: the textbook in-place type change. 5-run calibration peaks 547, 567, 579, 532, 523 ms against a 500 ms budget:
it fails, but only by 5-15%. On faster hardware the rewrite could finish inside the budget, which the ticket would legitimately accept.
So it is not used as a must-fail check.
