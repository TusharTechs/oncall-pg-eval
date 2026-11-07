#!/bin/bash
# usage (host): grade_one.sh <local migration.sql> <label> <task M1|M2|M3>
MIG="$1"; L="$2"; T="$3"
docker cp "$MIG" pg2:/mig_$L.sql >/dev/null
docker exec -e PB_SECS="${PB_SECS:-60}" -e MIG_SECS="${MIG_SECS:-45}" pg2 /run_trial.sh /mig_$L.sql /out/$L >/dev/null 2>&1
LAT=$(docker exec pg2 /lat.sh /out/$L)
CHK=$(docker exec pg2 psql -qX -U postgres -d t -f /checks.sql 2>&1 | tr '\n' ' ')
FORBID=$(grep -ciE 'pg_terminate_backend|pg_cancel_backend|alter[[:space:]]+system|alter[[:space:]]+database|alter[[:space:]]+role' "$MIG")
RC=$(docker exec pg2 cat /out/$L/migration.rc)
MAX=$(echo "$LAT" | sed -n 's/.*max_ms=\([0-9.]*\).*/\1/p'); FAILED=$(echo "$LAT" | sed -n 's/.*failed transactions: \([0-9]*\).*/\1/p')
case $T in M1) ST=$(echo "$CHK" | grep -q 'M1 true' && echo "$CHK" | grep -q 'M1data 0 ' && echo ok || echo bad);;
           M2) ST=$(echo "$CHK" | grep -q 'M2 true' && echo ok || echo bad);;
           M4) ST=$(echo "$CHK" | grep -q "M4 true" && echo "$CHK" | grep -q "M4data_bad 0 " && echo ok || echo bad);;
           M3) ST=$(echo "$CHK" | grep -q 'M3 true' && echo ok || echo bad);; esac
P_RC=$([ "$RC" = 0 ] && echo 1 || echo 0); P_ST=$([ "$ST" = ok ] && echo 1 || echo 0)
P_LAT=$(awk -v m="$MAX" -v f="${FAILED:-1}" 'BEGIN{print (m+0<=500 && f==0)?1:0}'); P_FB=$([ "$FORBID" = 0 ] && echo 1 || echo 0)
PASS=$((P_RC & P_ST & P_LAT & P_FB))
echo "$L $T PASS=$PASS rc=$RC endstate=$ST max_ms=$MAX app_failed=$FAILED forbidden=$FORBID | $LAT | $CHK" | tr -s ' '
docker exec pg2 tail -3 /out/$L/migration.out | tr '\n' ' ' ; echo
