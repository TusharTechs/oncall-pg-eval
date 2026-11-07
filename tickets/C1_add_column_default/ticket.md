## Ticket C1: add a column with a default
Add a column `region text NOT NULL DEFAULT 'EU'` to `orders`. Existing rows, rows the app inserts during the migration, and rows it inserts later must all have `region = 'EU'`.
