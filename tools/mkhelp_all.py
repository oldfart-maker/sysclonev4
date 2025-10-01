#!/usr/bin/env python3
import re, sys
from collections import OrderedDict

flt = sys.argv[1] if len(sys.argv) > 1 else ""
files = sys.argv[2:] if len(sys.argv) > 2 else []

target_re = re.compile(r"""^([A-Za-z0-9._+-]+)\s*:(?:[^=].*)?\s*##\s*(.+)$""")

seen = OrderedDict()
for path in files:
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                m = target_re.match(line.rstrip("\n"))
                if not m:
                    continue
                name, desc = m.group(1), m.group(2).strip()
                if flt and flt not in name and flt not in desc:
                    continue
                if name not in seen:
                    seen[name] = desc
    except FileNotFoundError:
        continue

if not seen:
    print(f"(no targets matched filter: {flt})" if flt else "(no targets with '##' docs found)")
    sys.exit(0)

w = max(len(k) for k in seen.keys())
for k, v in seen.items():
    print(f"{k:<{w}}  {v}")
