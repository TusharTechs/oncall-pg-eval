```sql
-- STATUS: BLOCKED: inside the mandatory single transaction CREATE INDEX CONCURRENTLY is impossible, and any in-transaction unique index build holds a SHARE (or ACCESS EXCLUSIVE) lock on orders blocking app writes for the 5-10s build until commit (>500 ms); no dblink to escape the wrapper.
```
