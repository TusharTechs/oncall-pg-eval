## Ticket C2: enforce customer_id
Make `orders.customer_id` NOT NULL as a real column constraint (`pg_attribute.attnotnull = true`) and enforce it with a validated foreign key to `customers(id)` (a `pg_constraint` row with `contype = 'f'` and `convalidated = true`). Extra helper constraints may remain or be dropped.
