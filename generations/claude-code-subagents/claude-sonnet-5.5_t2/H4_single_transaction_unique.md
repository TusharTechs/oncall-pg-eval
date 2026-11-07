```sql
-- STATUS: BLOCKED: unique index on 5M rows needs CREATE INDEX CONCURRENTLY (illegal inside the mandatory single transaction); a plain build blocks app writes for 5-10s, far over the 500 ms limit
```
