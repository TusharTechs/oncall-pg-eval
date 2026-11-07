```sql
-- STATUS: BLOCKED: a unique index on 5M rows must be built with CREATE INDEX CONCURRENTLY, which cannot run inside the mandatory single transaction; a plain build/ADD CONSTRAINT UNIQUE blocks app writes for 5-10s, far over the 500 ms limit
```
