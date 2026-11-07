```sql
-- STATUS: BLOCKED: a unique index needs CREATE INDEX CONCURRENTLY (forbidden inside the mandatory single transaction); a non-concurrent build holds a write-blocking SHARE lock for 5-10s, breaking the 500 ms app limit.
```
