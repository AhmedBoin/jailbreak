import sys, re

path = sys.argv[1]
needles = [s.encode() for s in sys.argv[2:]]
data = open(path, "rb").read()

for n in needles:
    hits = [m.start() for m in re.finditer(re.escape(n), data)]
    print("%-40r %d hits" % (n, len(hits)), " ".join("0x%X" % h for h in hits[:12]))
