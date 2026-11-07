## Ticket C3: unique external_ref
Add a UNIQUE constraint on `orders(external_ref)`: a `pg_constraint` row with `contype = 'u'` on exactly that column, backed by a valid index. Building a unique index on this column takes roughly 5–10 seconds on this machine.
