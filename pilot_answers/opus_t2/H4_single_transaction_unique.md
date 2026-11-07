```sql
-- STATUS: BLOCKED: under the mandatory single-transaction wrapper CREATE INDEX CONCURRENTLY is impossible, and a plain unique index build holds a SHARE lock on orders for 5-10 s, blocking app writes far beyond 500 ms
```
