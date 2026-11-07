```sql
-- STATUS: BLOCKED: a UNIQUE constraint needs a 5-10s index build; inside one wrapper transaction CREATE INDEX CONCURRENTLY is impossible, so the build holds a SHARE lock that blocks all app writes far beyond 500 ms, and the wrapper cannot be bypassed.
```
