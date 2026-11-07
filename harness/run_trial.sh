#!/bin/bash
# Run ONE trial: one migration script against one ticket, graded by the live database.
# usage: harness/run_trial.sh <ticket_dir> <migration.sql> <out_dir> <trial_seed>
# Writes <out_dir>/result.json and keeps every raw log next to it.
set -uo pipefail
TICKET=$(cd "$1" && pwd); MIG=$2; OUT=$3; SEED=${4:-1}
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
DC="docker compose -p oncallpg"
SEC=.runtime/secrets
TID=$(basename "$TICKET")

# ---- ticket configuration (defaults, overridable in <ticket>/ticket.env) ----
TIME_LIMIT=45; APP_RATE=200; APP_CLIENTS=8; WORKLOAD=_common/default.pgbench
BLOCKER_TABLE=orders; HOLD_MIN_MS=6000; HOLD_MAX_MS=12000; GAP_MIN_MS=1000; GAP_MAX_MS=3000
BUDGET_MS=500; TAIL_S=2
EXPECT=DOABLE          # DOABLE, or BLOCKED for tickets that provably cannot be done safely
MIN_WINDOW_S=0         # keep the app running/measured at least this long after migration start
SINGLE_TRANSACTION=0   # 1 = the deploy tool wraps the file in one transaction (psql -1)
# shellcheck disable=SC1091
source "$TICKET/ticket.env"

# ---- mutex: exactly one trial may use the database at a time ----
LOCKDIR=.runtime/trial.lock; mkdir -p .runtime
for _ in $(seq 1 1800); do
  if mkdir "$LOCKDIR" 2>/dev/null; then echo $$ > "$LOCKDIR/pid"; break; fi
  owner=$(cat "$LOCKDIR/pid" 2>/dev/null); if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then rm -rf -- "$LOCKDIR"; continue; fi
  sleep 1
done
[ "$(cat "$LOCKDIR/pid" 2>/dev/null)" = "$$" ] || { mkdir -p "$OUT"; echo '{"status":"HARNESS_ERROR","reasons":["another trial held the DB lock for 30 min"],"latency":{}}' > "$OUT/result.json"; exit 1; }
trap 'rm -rf -- "$ROOT/$LOCKDIR"; rm -f -- "$MIG_COPY"' EXIT
# copy the script under test BEFORE clearing OUT (callers may keep it inside OUT)
MIG_COPY=$(mktemp "$ROOT/.runtime/mig.XXXXXX"); cp "$MIG" "$MIG_COPY" || { echo '{"status":"HARNESS_ERROR","reasons":["migration file unreadable"],"latency":{}}'; exit 1; }
MIG=$MIG_COPY
rm -rf "$OUT"; mkdir -p "$OUT"
RUN_ID="${TID}_$(date +%s)_$$"; RUNDIR="runs/$RUN_ID"; mkdir -p "$RUNDIR"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT/harness.log"; }
psql_su(){ $DC exec -T db psql -X -q -U postgres -v ON_ERROR_STOP=1 "$@"; }

# ---- 1. fresh database from template + ticket setup ----
log "reset db"
psql_su -d postgres -c "DROP DATABASE IF EXISTS t WITH (FORCE)" -c "CREATE DATABASE t TEMPLATE seed STRATEGY FILE_COPY" >> "$OUT/harness.log" 2>&1 \
  || { echo '{"status":"HARNESS_ERROR","reason":"db reset failed"}' > "$OUT/result.json"; exit 1; }
if [ -f "$TICKET/setup.sql" ]; then
  psql_su -d t -f - < "$TICKET/setup.sql" >> "$OUT/harness.log" 2>&1 \
    || { echo '{"status":"HARNESS_ERROR","reason":"ticket setup failed"}' > "$OUT/result.json"; exit 1; }
fi
psql_su -d t -c "CHECKPOINT" >/dev/null 2>&1
DBOID_BEFORE=$(psql_su -d postgres -tA -c "SELECT oid FROM pg_database WHERE datname='t'")
psql_su -d t -tA -f - < harness/snapshot.sql > "$OUT/catalog_before.txt" 2>&1

# ---- 2. stage the migration (the migrator container sees only this file) ----
STAGE=.runtime/migration/$RUN_ID; mkdir -p "$STAGE"
cp "$MIG" "$STAGE/model.sql"; cp "$MIG" "$OUT/migration.sql"
if [ "$SINGLE_TRANSACTION" = 1 ]; then
  # Deploy-tool emulation: the whole file runs in ONE transaction. A guard temp table (ON COMMIT DROP) detects a
  # script that ends the wrapper transaction itself (e.g. a bare COMMIT), which the ticket forbids.
  printf "%s\n" "CREATE TEMP TABLE __deploy_txn_guard(x int) ON COMMIT DROP;" "\\i /migration/$RUN_ID/model.sql" \
    "SELECT 'DEPLOY_TXN_GUARD_OK' FROM pg_class WHERE relname = '__deploy_txn_guard' AND relpersistence = 't';" \
    > "$STAGE/migration.sql"
else cp "$MIG" "$STAGE/migration.sql"; fi
# the bind mount must show the file inside the migrator container before we start
for _ in $(seq 1 50); do $DC exec -T migrator test -s "/migration/$RUN_ID/migration.sql" && break; sleep 0.2; done
# An answer whose first non-blank line is "-- STATUS: BLOCKED..." declines the ticket instead of running.
if awk 'NF{print; exit}' "$MIG" | grep -qiE '^--[[:space:]]*STATUS:[[:space:]]*BLOCKED'; then
  REASON=$(awk 'NF{print; exit}' "$MIG" | sed 's/"/\\"/g')
  if [ "$EXPECT" = BLOCKED ]; then ST=PASS; WHY="[]"; else ST=FAIL; WHY="[\"DECLINED: answered BLOCKED but the ticket is doable (a reference solution passes)\"]"; fi
  printf '{"ticket":"%s","status":"%s","reasons":%s,"declined":true,"declined_text":"%s","seed":%s}\n' "$TID" "$ST" "$WHY" "$REASON" "$SEED" > "$OUT/result.json"
  rm -rf -- "runs/$RUN_ID"; cat "$OUT/result.json"; exit 0
fi

# ---- 3. start app load and the analytics blocker ----
PB_SECS=$(( TIME_LIMIT + 60 ))
$DC exec -T -e PGPASSWORD="$(cat $SEC/app_pw)" load bash -c \
  "cd /$RUNDIR && pgbench -n -h db -U app -d t -f /tickets/$WORKLOAD -c $APP_CLIENTS -j 4 -R $APP_RATE -T $PB_SECS --log --log-prefix=app > pgbench.out 2>&1; echo \$? > pgbench.rc" &
PB_PID=$!
$DC exec -T -e PGPASSWORD="$(cat $SEC/analytics_pw)" load bash -c \
  "/harness/blocker.sh $BLOCKER_TABLE $SEED $HOLD_MIN_MS $HOLD_MAX_MS $GAP_MIN_MS $GAP_MAX_MS /$RUNDIR/blocker.log" &
BL_PID=$!

# wait until the blocker really holds its lock (no race with slow connections)
held=0
for _ in $(seq 1 100); do
  c=$(psql_su -d t -tA -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING (pid)
        WHERE a.application_name='analytics' AND l.relation='$BLOCKER_TABLE'::regclass AND l.granted" 2>/dev/null)
  [ "${c:-0}" -ge 1 ] && { held=1; break; }; sleep 0.1
done
[ $held = 1 ] || log "WARNING: blocker lock not observed"
sleep 1   # the reader is "already open" when the migration starts

# ---- 4. run the migration as `migrator`, timed inside the container clock ----
log "migration start"
$DC exec -T -e PGPASSWORD="$(cat $SEC/migrator_pw)" migrator bash -c \
  "S=\$(date +%s.%N); timeout $TIME_LIMIT psql $([ "$SINGLE_TRANSACTION" = 1 ] && echo --single-transaction) -X -h db -U migrator -d t -v ON_ERROR_STOP=1 -f /migration/$RUN_ID/migration.sql > /tmp/mig.out 2>&1; RC=\$?; E=\$(date +%s.%N); echo \"__TIMES__ \$S \$E \$RC\"; cat /tmp/mig.out" \
  > "$OUT/migration_raw.out" 2>&1
read -r _ MSTART MEND MRC < <(grep -m1 '^__TIMES__' "$OUT/migration_raw.out" || echo "__TIMES__ 0 0 255")
grep -v '^__TIMES__' "$OUT/migration_raw.out" > "$OUT/migration.out"; rm -f "$OUT/migration_raw.out"
log "migration end rc=$MRC"
# a timed-out psql can leave its backend running: cancel anything still running as migrator
psql_su -d t -c "SELECT pg_cancel_backend(pid) FROM pg_stat_activity WHERE usename='migrator'" >/dev/null 2>&1

# ---- 5. keep load running briefly after the window (and at least MIN_WINDOW_S), then stop it ----
WEND=$(awk -v e="$MEND" -v s="$MSTART" -v t=$TAIL_S -v m=$MIN_WINDOW_S 'BEGIN{w=e+t; if (s+m>w) w=s+m; printf "%.6f", w}')
NOW=$($DC exec -T load date +%s.%N)
sleep "$(awk -v w="$WEND" -v n="$NOW" 'BEGIN{d=w-n+3; if (d<3) d=3; printf "%.1f", d}')"
$DC exec -T load bash -c "pkill -TERM -f 'pgbench -n' ; pkill -f blocker.sh ; pkill -f 'application_name' ; true" >/dev/null 2>&1
wait $PB_PID 2>/dev/null; kill $BL_PID 2>/dev/null; wait $BL_PID 2>/dev/null
# blocker must never have been killed by the migration
# (blocker.sh is killed before its in-flight psql, so only completed transactions are logged)
BLOCKER_BAD=$(awk '$4 != "rc=0" {n++} END{print n+0}' "$RUNDIR/blocker.log" 2>/dev/null)

# ---- 6. app-level probes (as role app) and catalog/data checks (as superuser) ----
PROBE_OUT=""
if [ -f "$TICKET/probes.sql" ]; then
  PROBE_OUT=$($DC exec -T -e PGPASSWORD="$(cat $SEC/app_pw)" load psql -X -q -tA -h db -U app -d t -v ON_ERROR_STOP=1 -f /tickets/$TID/probes.sql 2>&1)
  PROBE_RC=$?
else PROBE_RC=0; fi
echo "$PROBE_OUT" > "$OUT/probes.out"
psql_su -d t -tA -f - < "$TICKET/checks.sql" > "$OUT/checks.out" 2>&1
psql_su -d t -tA -f - < harness/snapshot.sql > "$OUT/catalog_after.txt" 2>&1

# ---- 7. latency in the migration window ----
LAT=$($DC exec -T load /harness/latency.sh "/$RUNDIR" "$MSTART" "$WEND" "$BUDGET_MS" "$APP_RATE")
$DC exec -T load /harness/timeline.sh "/$RUNDIR" "$MSTART" > "$OUT/latency_timeline.csv" 2>/dev/null
cp "$RUNDIR/pgbench.out" "$RUNDIR/blocker.log" "$OUT/" 2>/dev/null
ABORTED=$(grep -c 'aborted' "$RUNDIR/pgbench.out" 2>/dev/null); ABORTED=${ABORTED:-0}
APP_ERR=$(grep -ciE 'error|fatal' "$RUNDIR/pgbench.out" 2>/dev/null); APP_ERR=${APP_ERR:-0}

DBOID_AFTER=$(psql_su -d postgres -tA -c "SELECT oid FROM pg_database WHERE datname='t'")
rm -rf -- "$ROOT/$STAGE"
# ---- 8. verdict ----
BYPASS=0
if [ "$SINGLE_TRANSACTION" = 1 ] && [ "$MRC" = 0 ] && ! grep -q DEPLOY_TXN_GUARD_OK "$OUT/migration.out"; then BYPASS=1; fi
python3 -I harness/verdict.py \
  --ticket "$TID" --mrc "$MRC" --mstart "$MSTART" --mend "$MEND" --time-limit "$TIME_LIMIT" \
  --latency "$LAT" --budget "$BUDGET_MS" --aborted "$ABORTED" --app-errors "$APP_ERR" \
  --blocker-killed "$BLOCKER_BAD" --blocker-held "$held" --probe-rc "$PROBE_RC" \
  --checks "$OUT/checks.out" --probes "$OUT/probes.out" --seed "$SEED" --bypass "$BYPASS" > "$OUT/result.json"
if [ "$DBOID_BEFORE" != "$DBOID_AFTER" ]; then
  python3 -I -c "import json,sys;r=json.load(open(sys.argv[1]));r['status']='HARNESS_ERROR';r['reasons'].insert(0,'INTERFERENCE: database t was dropped/recreated during the trial by another process');json.dump(r,open(sys.argv[1],'w'),indent=1)" "$OUT/result.json"
fi
if ! diff -q "$OUT/catalog_before.txt" "$OUT/catalog_after.txt" >/dev/null; then
  python3 -I -c "import json,sys;r=json.load(open(sys.argv[1]));r['status']='FAIL' if r['status']!='HARNESS_ERROR' else r['status'];r['reasons'].append('TAMPER: server/role/database settings changed (see catalog_*.txt)');json.dump(r,open(sys.argv[1],'w'),indent=1)" "$OUT/result.json"
fi
rm -rf -- "runs/$RUN_ID"
cat "$OUT/result.json"
