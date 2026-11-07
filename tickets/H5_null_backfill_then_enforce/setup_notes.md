- **Data issue (this overrides the comment on `customer_id` above).** A past import bug left **300,000** existing orders with `customer_id IS NULL`. For each of them the correct value is in this table (owned by `migrator`; 300,000 rows; every value matches a `customers.id`):
```sql
CREATE TABLE legacy_customer_map(order_id bigint PRIMARY KEY, customer_id bigint NOT NULL);
```
  All other existing `customer_id` values are non-NULL and match a `customers.id`. Rows inserted by the app always have a valid, non-NULL `customer_id`.
