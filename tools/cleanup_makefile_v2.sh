#!/usr/bin/env bash
set -euo pipefail
mf="Makefile"
tmp="$mf.__tmp__"
bak="$mf.bak.$(date +%Y%m%d-%H%M%S)"

cp -a "$mf" "$bak"

# Targets to hard-delete
targets=(
  seed-layer2-all
  seed-layer2-all-fresh
  seed-all
  seed-layer1-all
  clear-layer-stamps
  zap-layer-stamps
  seed-layer-all
)

# Normalize CRLF just for processing
nl=$'\n'
clean="$(sed 's/\r$//' "$mf")"

# Build a set for quick membership
declare -A kill; for t in "${targets[@]}"; do kill["$t"]=1; done

# AWK pass: drop full rule blocks for listed targets
# Rule header heuristic: start of line, not space/tab/#, contains a colon before a '='
echo "$clean" | awk -v RS="$nl" -v ORS="$nl" '
  function is_rule_header(line) {
    # starts non-space, has ":" and not like "VAR := ..."
    if (line ~ /^[^ \t#][^:]*:/) {
      # exclude make variable defs like "FOO:=bar" or "FOO = bar"
      if (line ~ /^[^ \t#][^:=]*:[^=]/) return 1;
    }
    return 0;
  }
  { print }
' > "$tmp" # we’ll actually do the deletion in bash (more robust for multi-target headers)

# Bash parse: remove blocks for each target explicitly
mapfile -t lines < "$tmp"
> "$tmp"

in_skip=0
header_target=""
emit() { printf '%s\n' "$1" >> "$tmp"; }

get_header_target() {
  # first token before ":" (strip trailing spaces)
  local L="$1"
  local H="${L%%:*}"
  # keep only the last token (handles "a b: ..." weirdness)
  H="${H##* }"
  printf '%s' "$H"
}

for L in "${lines[@]}"; do
  if [[ $in_skip -eq 1 ]]; then
    # Stop skipping when we hit a new rule header
    if [[ "$L" =~ ^[^[:space:]#][^:]*: ]]; then
      in_skip=0
      header_target="$(get_header_target "$L")"
      if [[ -n "${kill[$header_target]+x}" ]]; then
        echo "[remove] $header_target" >&2
        in_skip=1
        continue
      else
        emit "$L"
      fi
    else
      # still inside the recipe/blank lines/comments of the killed rule
      continue
    fi
  else
    if [[ "$L" =~ ^[^[:space:]#][^:]*: ]]; then
      header_target="$(get_header_target "$L")"
      if [[ -n "${kill[$header_target]+x}" ]]; then
        echo "[remove] $header_target" >&2
        in_skip=1
        continue
      fi
    fi
    emit "$L"
  fi
done

# Remove killed targets from any .PHONY lines
sed -E -i '
  /^\.[Pp][Hh][Oo][Nn][Yy]:/{
    s/(^\.PHONY:[[:space:]]*)/\1/;
    s/\<seed-layer2-all\>//g;
    s/\<seed-layer2-all-fresh\>//g;
    s/\<seed-all\>//g;
    s/\<seed-layer1-all\>//g;
    s/\<clear-layer-stamps\>//g;
    s/\<zap-layer-stamps\>//g;
    s/\<seed-layer-all\>//g;
    s/[[:space:]]+/ /g;
  }
' "$tmp"

# Ensure check-stamps / show-stamps exist
need_check=1; need_show=1
grep -qE '^[[:space:]]*check-stamps:' "$tmp" && need_check=0 || true
grep -qE '^[[:space:]]*show-stamps:'  "$tmp" && need_show=0  || true

{
  cat "$tmp"
  echo
  echo "# ===== Section: utils ======================================================"
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
  echo "# ===== Section: layer1 ====================================================="
  echo "# ===== Section: layer2 ====================================================="
  echo "# ===== Section: layer2.5 ==================================================="
  echo "# ===== Section: layer-all =================================================="
} > "$mf"

rm -f "$tmp"
echo "Done. Backup stored at: $bak"
