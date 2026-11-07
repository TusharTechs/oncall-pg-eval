```sql
-- STATUS: BLOCKED: --single-transaction forbids CREATE INDEX CONCURRENTLY and no dblink exists, so the 5-10s unique index build must hold a SHARE/ACCESS EXCLUSIVE lock on orders and block app writes far beyond 500 ms.
```
