"""Trim GeoNames cities15000 into Resources/cities.tsv for TimeAlign.
Columns out: name, subtitle ("State, Country"), tz id, population, aliases (comma-separated)."""
import os, re, sys
src, out = sys.argv[1], sys.argv[2]
SHORT = {"US": "USA", "GB": "UK", "AE": "UAE"}
countries = {}
for line in open(os.path.join(src, "countryInfo.txt"), encoding="utf-8"):
    if line.startswith("#"): continue
    f = line.rstrip("\n").split("\t")
    countries[f[0]] = SHORT.get(f[0], f[4])
admin1 = {}
for line in open(os.path.join(src, "admin1CodesASCII.txt"), encoding="utf-8"):
    f = line.rstrip("\n").split("\t")
    admin1[f[0]] = f[1]
latin = re.compile(r"^[A-Za-z][A-Za-z .'-]{3,}$")
rows = []
for line in open(os.path.join(src, "cities15000.txt"), encoding="utf-8"):
    f = line.rstrip("\n").split("\t")
    name, alts, cc, a1, pop, tz = f[1], f[3], f[8], f[10], int(f[14] or 0), f[17]
    if not tz or not os.path.exists("/usr/share/zoneinfo/" + tz): continue
    country = countries.get(cc, cc)
    state = admin1.get(f"{cc}.{a1}", "")
    subtitle = f"{state}, {country}" if state and state != name else country
    aliases = []
    if pop >= 500_000:   # well-known old/English names (Bangalore, Bombay, Peking)
        seen = {name.lower()}
        for a in alts.split(","):
            if latin.match(a) and a.lower() not in seen and len(aliases) < 6:
                seen.add(a.lower()); aliases.append(a)
    rows.append((pop, name, subtitle, tz, aliases))
rows.sort(key=lambda r: -r[0])
with open(out, "w", encoding="utf-8") as o:
    for pop, name, subtitle, tz, aliases in rows:
        o.write("\t".join([name, subtitle, tz, str(pop), ",".join(aliases)]) + "\n")
print(len(rows), "cities ->", out, os.path.getsize(out), "bytes")
