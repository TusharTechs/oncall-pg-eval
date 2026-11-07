```sql
-- Emergency fix, no table rewrite and no table lock: move the identity sequence into the
-- unused NEGATIVE half of the int range. Existing ids (just below 2147483647) never change,
-- and the sequence now has ~2.1 billion values (-2147483648 .. -1 and beyond) before it can
-- possibly collide with them, far more than the 1,000,000,000 required.
-- The column can be widened to bigint later in a maintenance window.
ALTER SEQUENCE events_id_seq MINVALUE -2147483648 RESTART WITH -2147483648;
```
