#!/usr/bin/env python3
from pathlib import Path
mf = Path("Makefile")
bak = Path(f"Makefile.bak.insert-net-{__import__('time').strftime('%Y%m%d%H%M%S')}")
bak.write_text(mf.read_text())

text = mf.read_text()

start = text.find("\nseed-layer1-all:")
if start == -1:
    raise SystemExit("seed-layer1-all target not found")

# Find the recipe block: from first newline after header to the first blank line OR next non-tab line
line_start = text.find("\n", start) + 1
i = line_start
n = len(text)
while i < n:
    # stop when we hit a blank line or a non-tab-started line
    j = text.find("\n", i)
    if j == -1: j = n
    line = text[i:j]
    if line.strip() == "":    # blank line ends recipe
        break
    if not (line.startswith("\t") or line.startswith(" ") or line.startswith("@")):
        # conservative: if it doesn't look indented, stop
        break
    i = j + 1

block = text[line_start:i]
if "$(MAKE) seed-layer1-net-bootstrap" in block:
    # already wired, write original back and exit
    print("[hook] seed-layer1-net-bootstrap already present in aggregate; no change.")
    raise SystemExit(0)

lines = block.splitlines()
out = []
inserted = False
for L in lines:
    out.append(L)
    if "$(MAKE) seed-layer1-expand-rootfs" in L and not inserted:
        # keep indentation style from the line we’re following
        indent = L[:len(L) - len(L.lstrip())]
        # if the followed line ends with a backslash, we keep backslash as well
        has_bslash = L.rstrip().endswith("\\")
        # our aggregate lines use trailing backslashes in this file; keep that
        out.append(f"{indent}$(MAKE) seed-layer1-net-bootstrap; \\")
        inserted = True

# if we didn’t find the expand-rootfs line, don’t guess—write back original unchanged
if not inserted:
    print("[hook] WARNING: could not locate the expand-rootfs call inside seed-layer1-all; no change made.")
    raise SystemExit(0)

new_block = "\n".join(out) + ("\n" if block.endswith("\n") else "")
new_text = text[:line_start] + new_block + text[i:]
mf.write_text(new_text)
print(f"[hook] updated Makefile (backup at {bak})")
