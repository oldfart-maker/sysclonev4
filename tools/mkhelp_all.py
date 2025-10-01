#!/usr/bin/env python3
import re, sys, os
from collections import OrderedDict

# Usage:
#   python mkhelp_all.py "<filter or empty>" <file1> <file2> ...
# We’ll scan all files and print "target: description" lines for any rule
# like:   target: ... ## description
flt = sys.argv[1] if len(sys.argv) > 1 else ""
files = sys.argv[2:] if len(sys.argv) > 2 else []

target_re = re.compile(r"""^
    (?P<name>[A-Za-z0-9._+-]+)    # target
    \s*:
    (?:[^=].*)?                   # avoid var assignments like VAR:=...
    \s*##\s*(?P<desc>.+)$
""", re.VERBOSE)

seen = OrderedDict()

for path in files:
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                m = target_re.match(line.rstrip("\n"))
                if not m:
                    continue
                name = m.group("name")
                desc = m.group("desc").strip()
                if flt and flt not in name and flt not in desc:
                    continue
                # keep first occurrence to avoid noisy dupes
                if name not in seen:
                    seen[name] = desc
    except FileNotFoundError:
        # Ignore missing includes; MAKEFILE_LIST can include non-existent optionals
        continue

if not seen:
    if flt:
        print(f"(no targets matched filter: {flt})")
    else:
        print("(no targets with '##' docs found)")
    sys.exit(0)

# Pretty print aligned
w = max(len(k) for k in seen.keys())
for k, v in seen.items():
    print(f"{k:<{w}}  {v}")
