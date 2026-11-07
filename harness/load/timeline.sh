#!/bin/bash
# Per-second app latency timeline relative to migration start (for plots / the video).
# Buckets each transaction by its SCHEDULED START (completion time - latency), so a stall shows as the queue it is
# (transactions arriving during the stall wait longest), not as a gap followed by one spike. Ignores malformed lines.
# usage: timeline.sh <dir> <migration_start_epoch>   -> CSV: second,tx_started,max_latency_ms,mean_latency_ms
cat "$1"/app.* 2>/dev/null | awk -v s="$2" '
  $5 > 1000000000 { lat = $3 / 1e6; start = ($5 + $6/1e6) - lat; sec = int(start - s + 1000) - 1000;
                    c[sec]++; sum[sec] += lat*1000; if (lat*1000 > m[sec]) m[sec] = lat*1000 }
  END { print "second,tx_started,max_latency_ms,mean_latency_ms"; for (k in c) printf "%d,%d,%.1f,%.1f\n", k, c[k], m[k], sum[k]/c[k] }' \
 | (read -r h; echo "$h"; sort -t, -k1,1n)
