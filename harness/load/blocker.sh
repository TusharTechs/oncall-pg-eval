#!/bin/bash
# Analytics blocker loop (runs in the `load` container as role `analytics`).
# Repeats: open a read transaction on $TABLE, hold it for a random 6..12 s, commit,
# pause a random 1..3 s. Seeded, so a trial's schedule is reproducible. Logs each txn.
# usage: blocker.sh <table> <seed> <hold_min_ms> <hold_max_ms> <gap_min_ms> <gap_max_ms> <logfile>
T=$1; RANDOM=$2; HMIN=$3; HMAX=$4; GMIN=$5; GMAX=$6; LOG=$7
: > "$LOG"
while true; do
  H=$(( HMIN + RANDOM % (HMAX - HMIN + 1) ))
  S=$(date +%s.%N)
  psql -X -q -h db -U analytics -d t -v ON_ERROR_STOP=1 \
    -c "SET application_name = 'analytics'" -c "BEGIN" \
    -c "SELECT count(*) FROM $T WHERE id < 1000" \
    -c "SELECT pg_sleep($H / 1000.0)" -c "COMMIT" >/dev/null 2>>"$LOG.err"
  RC=$?
  echo "$S $(date +%s.%N) hold_ms=$H rc=$RC" >> "$LOG"
  G=$(( GMIN + RANDOM % (GMAX - GMIN + 1) ))
  sleep "$(awk -v g=$G 'BEGIN{printf "%.3f", g/1000}')"
done
