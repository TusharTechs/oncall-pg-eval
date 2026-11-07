p(){ if su -s /bin/sh "$1" -c "$2" >/dev/null 2>&1; then echo "$3: YES"; else echo "$3: NO"; fi; }
p alice 'echo x >> /proj/a.txt' 'Q1 alice append to /proj/a.txt'
p bob 'cat /proj/a.txt' 'Q2 bob read /proj/a.txt'
p bob 'echo x >> /proj/a.txt' 'Q3 bob append to /proj/a.txt'
p carol 'cat /proj/a.txt' 'Q4 carol read /proj/a.txt'
p carol 'echo x >> /proj/a.txt' 'Q5 carol append to /proj/a.txt'
p carol 'ls /proj' 'Q6 carol list /proj'
p bob 'touch /proj/b.txt' 'Q7 bob create /proj/b.txt'
stat -c 'Q8 group of /proj/b.txt: %G' /proj/b.txt 2>/dev/null || echo 'Q8 n/a'
p bob 'rm -f /proj/a.txt' 'Q9 bob delete /proj/a.txt'
p dave 'echo x >> /shared/alice.log' 'Q10 dave append /shared/alice.log'
p dave 'rm -f /shared/alice.log' 'Q11 dave delete /shared/alice.log'
getfacl -p /proj/a.txt /proj 2>/dev/null
