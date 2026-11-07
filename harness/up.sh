#!/bin/bash
# Start the environment and build the seed template (idempotent). ~1-2 minutes.
set -euo pipefail
cd "$(dirname "$0")/.."
DC="docker compose -p oncallpg"
mkdir -p .runtime/secrets .runtime/migration runs
for r in superuser app analytics migrator; do
  f=.runtime/secrets/${r}_pw
  [ -s "$f" ] || openssl rand -hex 12 > "$f"
done
chmod 644 .runtime/secrets/*   # readable by the container's postgres user; never mounted into migrator
$DC up -d --wait
if [ "$($DC exec -T db psql -X -tA -U postgres -c "SELECT count(*) FROM pg_database WHERE datname='seed'")" != "1" ]; then
  echo "building seed template (5M rows)..."
  $DC exec -T db psql -X -q -U postgres -v ON_ERROR_STOP=1 -f - < harness/seed.sql
fi
$DC exec -T db psql -X -tA -U postgres -c "SELECT 'ready: ' || version()"
