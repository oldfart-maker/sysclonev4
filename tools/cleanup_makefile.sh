#!/usr/bin/env bash
set -euo pipefail

mf="Makefile"
cp -a "$mf" "$mf.bak.$(date +%Y%m%d-%H%M%S)"

# Aggregate targets to hard-delete
read -r -d '' AGGREGATES <<'EOF'
seed-layer2-all
seed-layer2-all-fresh
seed-all
seed-layer1-all
clear-layer-stamps
zap-layer-stamps
seed-layer-all
EOF

# Build an alternation for regex
alts="$(printf '%s\n' "$AGGREGATES" | awk 'NF{a=a (a?"|":"") $0}END{print a}')"

# 1) Remove rule blocks for those targets (target line + following recipe)
#    Heuristic: a rule starts at "TARGET:" and continues while lines start with TAB or are blank.
awk -v RS='\n' -v ORS='\n' -v TARGRE="^(""$alts"")\\s*:" '
  BEGIN { skip=0 }
  {
    line=$0
    if (skip==1) {
      # stop skipping when a new rule header is seen (non-indented "name:")
      if (match(line, /^[^ \t][^:]*:/)) { skip=0 } else { next }
    }
    if (match(line, TARGRE)) {
      skip=1
      next
    }
    print line
  }
' "$mf" > "$mf.tmp1"

# 2) Remove the same names from any .PHONY lines
#    (leave .PHONY itself in place)
sed -E "s/(^\\.PHONY:.*)(\\b($alts)\\b)/\\1/g; s/  +/ /g; s/: /: /" "$mf.tmp1" > "$mf.tmp2"

# 3) Ensure utils: check-stamps & show-stamps exist; if not, append minimal defs
need_check=1
need_show=1
grep -qE '^[[:space:]]*check-stamps:' "$mf.tmp2" && need_check=0 || true
grep -qE '^[[:space:]]*show-stamps:'  "$mf.tmp2" && need_show=0  || true

{
  cat "$mf.tmp2"

  echo
  echo "# ===== Section: utils ======================================================"
  echo "# (Added headers for readability; no reordering performed.)"
  echo

  if (( need_check )); then
    cat <<'MK'
.PHONY: check-stamps
check-stamps: ## check if known stamp files exist on mounted ROOT
@root="${ROOT_MNT:-/mnt/sysclone-root}"; \
for f in /var/lib/sysclone/first-boot.done \
         /var/lib/sysclone/.layer2-installed \
         /var/lib/sysclone/.layer2.5-greetd-installed; do \
  if [ -e "$$root$$f" ]; then echo "[stamp] $$f: PRESENT"; else echo "[stamp] $$f: missing"; fi; \
done
MK
    echo
  fi

  if (( need_show )); then
    cat <<'MK'
.PHONY: show-stamps
show-stamps: ## list all stamps under /var/lib/sysclone on mounted ROOT
@root="${ROOT_MNT:-/mnt/sysclone-root}"; \
if [ -d "$$root/var/lib/sysclone" ]; then \
  echo "[stamps] at $$root/var/lib/sysclone"; \
  ls -la "$$root/var/lib/sysclone"; \
else echo "[stamps] directory not found at $$root/var/lib/sysclone"; fi
MK
    echo
  fi
} > "$mf.tmp3"

# 4) Insert section headers (pure comments). We won’t shuffle targets today,
#    just prepend helpful banners if they don’t already appear.
insert_banner() {
  local label="$1"
  local tag="# ===== Section: $label ====="
  grep -qF "$tag" "$mf.tmp3" || printf "\n%s\n\n" "$tag" >> "$mf.tmp3"
}
insert_banner "layer1"
insert_banner "layer2"
insert_banner "layer2.5"
insert_banner "layer-all"
# utils header already added above

mv "$mf.tmp3" "$mf"
rm -f "$mf.tmp1" "$mf.tmp2"
echo "Makefile cleaned. Backup at $mf.bak.*"
