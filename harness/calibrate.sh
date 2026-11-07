#!/bin/bash
# Grader validation for one or more tickets: every reference must PASS N/N and
# every mutation (deliberately wrong script) must FAIL N/N.
# usage: harness/calibrate.sh <N> <ticket_dir> [<ticket_dir> ...]
# Writes results/calibration/<ticket>/<script>/run<k>/result.json and prints a summary table.
set -uo pipefail
cd "$(dirname "$0")/.."
N=$1; shift
for T in "$@"; do
  TID=$(basename "$T")
  for kind in reference mutations; do
    for f in "$T/$kind"/*.sql; do
      [ -f "$f" ] || continue
      name=$(basename "$f" .sql); passes=0; peaks=""
      for k in $(seq 1 "$N"); do
        out="results/calibration/$TID/$kind-$name/run$k"
        ./harness/run_trial.sh "$T" "$f" "$out" "$k" > /dev/null 2>&1
        [ -s "$out/result.json" ] || echo '{"status":"HARNESS_ERROR","reasons":["no result.json written"],"latency":{}}' > "$out/result.json"
        st=$(python3 -I -c "import json;r=json.load(open('$out/result.json'));print(r['status'])")
        pk=$(python3 -I -c "import json;r=json.load(open('$out/result.json'));print(r.get('latency',{}).get('max_ms','-'))")
        [ "$st" = PASS ] && passes=$((passes+1)); peaks="$peaks $pk"
        [ "$st" = HARNESS_ERROR ] && echo "  !! HARNESS_ERROR in $out"
      done
      want=$([ $kind = reference ] && echo "$N/$N pass" || echo "0/$N pass")
      got="$passes/$N pass"; ok=$([ "$got" = "$want" ] && echo OK || echo "** MISMATCH **")
      first_reason=$(python3 -I -c "import json;r=json.load(open('$out/result.json'));print((r['reasons'] or ['-'])[0][:70])")
      printf "%-24s %-10s %-34s %-10s peaks_ms=[%s ] %s | %s\n" "$TID" "$kind" "$name" "$got" "$peaks" "$ok" "$first_reason"
    done
  done
done
