#!/bin/bash
# usage (inside pg2 container): run_trial.sh <migration.sql|NONE> <outdir>
MIG="$1"; OUT="$2"; mkdir -p "$OUT"; rm -f "$OUT"/*
export PGUSER=postgres
psql -qX -c "DROP DATABASE IF EXISTS t WITH (FORCE)" -c "CREATE DATABASE t TEMPLATE seed" >/dev/null
cd "$OUT"
# app workload: 200 tx/s, 8 clients, 40 s, per-transaction log
pgbench -n -d t -f /app.pgbench -c 8 -j 4 -R 200 -T ${PB_SECS:-60} --log --log-prefix=app > pgbench.out 2>&1 &
PB=$!
sleep 3
# analytics job: open transaction reading orders, held 10 s
psql -qX -d t -c "BEGIN; SELECT count(*) FROM orders WHERE id < 1000; SELECT pg_sleep(10); COMMIT;" > analytics.out 2>&1 &
sleep 1
START=$(date +%s.%N)
if [ "$MIG" != NONE ]; then
  timeout ${MIG_SECS:-45} psql -X -d t -v ON_ERROR_STOP=1 -f "$MIG" > migration.out 2>&1; echo $? > migration.rc
else echo 0 > migration.rc; fi
END=$(date +%s.%N)
echo "$START $END" > migration.time
wait $PB
