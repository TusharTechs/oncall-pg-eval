```sql
-- STATUS: BLOCKED: inside the forced single transaction CREATE INDEX CONCURRENTLY is impossible, and any non-concurrent unique index/constraint build holds a write-blocking lock on orders for 5-10 s (>500 ms); no dblink/background tool exists to escape the transaction
```
