#!/bin/bash
# Summarize app latency inside the migration window [start, end].
# pgbench --log columns: client txn latency_us script epoch_s epoch_us [lag_us]
# Latency = pgbench per-transaction time; under -R it includes queueing (schedule lag),
# i.e. what the application actually experiences. Works with mawk (no gawk needed).
# usage: latency.sh <dir> <win_start> <win_end> <budget_ms> <expected_rate>
D=$1; S=$2; E=$3; B=$4; R=$5
cat "$D"/app.* 2>/dev/null \
 | awk -v s="$S" -v e="$E" '{ t = $5 + $6/1e6; if (t >= s && t <= e) printf "%.3f\n", $3/1000 }' \
 | sort -n \
 | awk -v b="$B" -v r="$R" -v s="$S" -v e="$E" '
   { n++; v[n]=$1; if ($1 > b) over++ }
   END { i = int(n*0.99); if (i < 1) i = 1;
         printf "{\"n\": %d, \"expected_n\": %.0f, \"max_ms\": %.1f, \"p99_ms\": %.1f, \"over_budget\": %d}\n",
                n, r*(e-s), (n ? v[n] : 0), (n ? v[i] : 0), over+0 }'
