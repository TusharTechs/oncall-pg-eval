## Ticket H3: unique external_ref (second attempt)
Add a UNIQUE constraint on `orders(external_ref)`: a `pg_constraint` row with `contype = 'u'` on exactly that column, backed by a valid index. When your script finishes there must be no invalid indexes on `orders`. Building a unique index on this column takes roughly 5–10 seconds on this machine.
