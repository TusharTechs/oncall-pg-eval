set -e
apt-get update -qq >/dev/null && apt-get install -y -qq acl >/dev/null
groupadd dev; useradd -m -G dev alice; useradd -m -G dev bob; useradd -m carol; useradd -m dave
mkdir /proj && chown alice:dev /proj && chmod 2770 /proj
touch /proj/a.txt && chown alice:dev /proj/a.txt && chmod 0460 /proj/a.txt
setfacl -m u:carol:rw- /proj/a.txt
setfacl -m m::r-x /proj/a.txt
setfacl -m u:carol:--x /proj
mkdir /shared && chmod 1777 /shared
su alice -c 'touch /shared/alice.log; chmod 666 /shared/alice.log'
chmod g-w /proj/a.txt
