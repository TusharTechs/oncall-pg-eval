You are being evaluated on three independent expert systems-engineering tasks. Answer from your own knowledge and reasoning only. Do NOT use any tools (no shell, no web, no file reads, no code execution). Reply with ONLY one JSON object in the exact schema at the end — no prose.

=====================================================================
TASK PERM — Linux permissions
=====================================================================
Environment: Debian 12 container, Linux kernel 6.8, filesystem supports POSIX ACLs. Kernel sysctls: fs.protected_regular=2, fs.protected_symlinks=1, fs.protected_hardlinks=1. Root runs this script once:

```
groupadd dev; useradd -m -G dev alice; useradd -m -G dev bob; useradd -m carol; useradd -m dave
mkdir /proj && chown alice:dev /proj && chmod 2770 /proj
touch /proj/a.txt && chown alice:dev /proj/a.txt && chmod 0460 /proj/a.txt
setfacl -m u:carol:rw- /proj/a.txt
setfacl -m m::r-x /proj/a.txt
setfacl -m u:carol:--x /proj
mkdir /shared && chmod 1777 /shared
su alice -c 'touch /shared/alice.log; chmod 666 /shared/alice.log'
chmod g-w /proj/a.txt
```

Then the following commands are run IN THIS ORDER, each as `su -s /bin/sh USER -c 'CMD'` (fresh login, groups per /etc/group). For Q1–Q7 and Q9–Q11 answer "YES" if the command exits 0, "NO" if it fails. For Q8 answer the group name.

Q1  alice: echo x >> /proj/a.txt
Q2  bob:   cat /proj/a.txt
Q3  bob:   echo x >> /proj/a.txt
Q4  carol: cat /proj/a.txt
Q5  carol: echo x >> /proj/a.txt
Q6  carol: ls /proj
Q7  bob:   touch /proj/b.txt
Q8  (no command) which group owns /proj/b.txt after Q7? (answer "n/a" if it does not exist)
Q9  bob:   rm -f /proj/a.txt
Q10 dave:  echo x >> /shared/alice.log
Q11 dave:  rm -f /shared/alice.log

=====================================================================
TASK PG — PostgreSQL 17 migration impact
=====================================================================
PostgreSQL 17.x, default configuration. Before EACH statement the tables are freshly recreated as:

```
CREATE TABLE customers(id bigint primary key);            -- 1,000 rows
CREATE TABLE orders(id bigint primary key, customer_id bigint, qty int, status text,
                    amount numeric(12,2), note varchar(100), created_at timestamp);  -- 200,000 rows, no NULLs
```
plus any "pre:" statement listed (already committed). Session TimeZone is 'UTC' unless the item says otherwise. Each statement is then run alone inside an explicit `BEGIN; <statement>; COMMIT;`.

For each item give:
- "lock": the STRONGEST table-level lock mode the transaction holds on `orders` just before COMMIT, using pg_locks names (AccessShareLock, RowShareLock, RowExclusiveLock, ShareUpdateExclusiveLock, ShareLock, ShareRowExclusiveLock, ExclusiveLock, AccessExclusiveLock), or "ERROR" if the statement fails.
- "rewrite": true if the orders table's heap is rewritten (pg_relation_filenode('orders') changes), else false.
- "scan": true if the statement reads through the whole orders heap (pg_stat_user_tables.seq_scan for orders increases), else false.

P01 ALTER TABLE orders ADD COLUMN region text DEFAULT 'EU'
P02 ALTER TABLE orders ADD COLUMN token uuid DEFAULT gen_random_uuid()
P03 ALTER TABLE orders ALTER COLUMN note TYPE varchar(200)
P04 ALTER TABLE orders ALTER COLUMN note TYPE varchar(50)
P05 ALTER TABLE orders ALTER COLUMN amount TYPE numeric(14,2)
P06 ALTER TABLE orders ALTER COLUMN amount TYPE numeric(12,4)
P07 ALTER TABLE orders ALTER COLUMN created_at TYPE timestamptz           (session TimeZone = 'UTC')
P08 ALTER TABLE orders ALTER COLUMN created_at TYPE timestamptz           (session TimeZone = 'America/New_York')
P09 ALTER TABLE orders ADD CONSTRAINT amt_pos CHECK (amount > 0) NOT VALID
P10 ALTER TABLE orders VALIDATE CONSTRAINT amt_pos      pre: ALTER TABLE orders ADD CONSTRAINT amt_pos CHECK (amount > 0) NOT VALID
P11 ALTER TABLE orders ALTER COLUMN status SET NOT NULL pre: ALTER TABLE orders ADD CONSTRAINT st_nn CHECK (status IS NOT NULL)
P12 ALTER TABLE orders ALTER COLUMN status SET NOT NULL
P13 ALTER TABLE orders ADD CONSTRAINT fk_c FOREIGN KEY (customer_id) REFERENCES customers(id) NOT VALID
P14 ALTER TABLE orders ALTER COLUMN qty TYPE bigint
P15 ALTER TABLE orders ALTER COLUMN note TYPE text
P16 CREATE INDEX orders_status_idx ON orders(status)
P17 ALTER TABLE orders ADD COLUMN ts timestamptz DEFAULT now()
P18 ALTER TABLE orders ADD COLUMN flag boolean NOT NULL DEFAULT false
P19 ALTER TABLE orders ADD COLUMN seq bigserial
P20 CREATE INDEX CONCURRENTLY orders_note_idx ON orders(note)

=====================================================================
TASK NETPOL — Kubernetes NetworkPolicy reachability
=====================================================================
The CNI fully and correctly implements networking.k8s.io/v1 NetworkPolicy and nothing else (no AdminNetworkPolicy, no mesh). Return traffic of an allowed connection is allowed. All traffic is pod-IP to pod-IP. No hostNetwork pods.

Namespaces and labels:
- prod: {kubernetes.io/metadata.name: prod, env: prod}
- staging: {kubernetes.io/metadata.name: staging, env: staging}
- monitoring: {kubernetes.io/metadata.name: monitoring, team: obs}
- kube-system: {kubernetes.io/metadata.name: kube-system}

Pods (namespace/name {labels} listening ports):
- prod/web {app: web} TCP 80
- prod/api {app: api} TCP 8080, TCP 9090
- prod/db {app: db} TCP 5432, TCP 9187
- prod/metrics {app: prometheus} TCP 9090
- staging/web {app: web} TCP 80
- monitoring/prom {app: prometheus} TCP 9090
- monitoring/grafana {app: grafana} TCP 3000
- kube-system/coredns {k8s-app: kube-dns} UDP 53, TCP 53

These are the ONLY NetworkPolicies in the cluster:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny-ingress, namespace: prod}
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: api-from-web, namespace: prod}
spec:
  podSelector: {matchLabels: {app: api}}
  ingress:
  - from:
    - podSelector: {matchLabels: {app: web}}
    ports:
    - {protocol: TCP, port: 8080}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: db-ingress, namespace: prod}
spec:
  podSelector: {matchLabels: {app: db}}
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector: {matchLabels: {team: obs}}
      podSelector: {matchLabels: {app: prometheus}}
  - from:
    - podSelector: {matchLabels: {app: api}}
    ports:
    - {protocol: TCP, port: 5432}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: web-egress, namespace: prod}
spec:
  podSelector: {matchLabels: {app: web}}
  policyTypes: [Egress]
  egress:
  - to:
    - podSelector: {matchLabels: {app: api}}
    ports:
    - {protocol: TCP, port: 8080}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: db-egress-lockdown, namespace: prod}
spec:
  podSelector: {matchLabels: {app: db}}
  policyTypes: [Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-all-namespaces, namespace: staging}
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector: {}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: metrics-scrape, namespace: prod}
spec:
  podSelector: {matchLabels: {app: api}}
  ingress:
  - from:
    - namespaceSelector: {matchLabels: {team: obs}}
    - podSelector: {matchLabels: {app: prometheus}}
    ports:
    - {protocol: TCP, port: 9090}
```

For each NEW connection attempt (TCP unless stated), answer "ALLOW" or "BLOCK":
N01 prod/web -> prod/api:8080
N02 prod/web -> prod/api:9090
N03 prod/web -> prod/db:5432
N04 prod/api -> prod/db:5432
N05 prod/api -> prod/db:9187
N06 monitoring/prom -> prod/db:9187
N07 prod/metrics -> prod/db:9187
N08 monitoring/grafana -> prod/db:9187
N09 monitoring/grafana -> prod/api:9090
N10 prod/metrics -> prod/api:9090
N11 monitoring/prom -> prod/api:8080
N12 staging/web -> prod/api:8080
N13 prod/db -> staging/web:80
N14 prod/api -> staging/web:80
N15 prod/web -> kube-system/coredns UDP 53
N16 prod/api -> monitoring/grafana:3000
N17 staging/web -> prod/web:80
N18 monitoring/prom -> staging/web:80
N19 prod/metrics -> prod/api:8080
N20 monitoring/prom -> prod/api:9090

=====================================================================
OUTPUT — exactly this JSON shape, nothing else:
{"PERM":{"Q1":"YES|NO",...,"Q8":"<group or n/a>",...,"Q11":"YES|NO"},
 "PG":{"P01":{"lock":"...","rewrite":true|false,"scan":true|false}, ... ,"P20":{...}},
 "NETPOL":{"N01":"ALLOW|BLOCK", ... ,"N20":"ALLOW|BLOCK"}}
