```sql
-- Emergency fix: the existing ids occupy the top ~2M values of the integer range, so
-- move the identity sequence to the bottom of the integer range instead. Ids then run
-- from -2147483648 upward (billions of values) and never touch existing rows.
-- ALTER SEQUENCE locks only the sequence (not the events table), so the app and the
-- analytics transaction are not blocked. The column type change to bigint can be
-- scheduled for a later maintenance window.
ALTER SEQUENCE events_id_seq MINVALUE -2147483648 RESTART WITH -2147483648;
```
