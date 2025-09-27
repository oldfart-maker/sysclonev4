#!/usr/bin/env bash
set -euo pipefail
mf="Makefile"
[ -f "$mf" ] || { echo "Makefile not found"; exit 1; }

bak="$mf.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "$mf" "$bak"

# Aggregates to hard-delete
kill_targets=(
  seed-layer2-all
  seed-layer2-all-fresh
  seed-all
  seed-layer1-all
  clear-layer-stamps
  zap-layer-stamps
  seed-layer-all
)

# Build an awk assoc array initializer
awk_kills='BEGIN{'
for t in "${kill_targets[@]}"; do awk_kills+="kill[\"$t\"]=1;"; done
awk_kills+='}'

# 1) Remove full rule blocks for those targets
awk -v RS='\n' -v ORS='\n' "$awk_kills
function is_header(l){ return (l ~ /^[^ \t#][^:]*:/) }
function header_has_kill(l){
  h=l; sub(/:.*/,\"\",h);
  n=split(h,arr,/[ \t]+/);
  for(i=1;i<=n;i++){ if(arr[i] in kill) return 1 }
  return 0
}
{
  if (skip) {
    if (is_header($0)) {
      # new header—decide whether to keep skipping
      if (header_has_kill($0)) { next } else { skip=0; print $0 }
    } else { next }
  } else {
    if (is_header($0) && header_has_kill($0)) {
      # start skipping this killed rule
      hdr=$0; sub(/:.*/,\"\",hdr);
      printf(\"[remove] %s\n\", hdr) > \"/dev/stderr\"
      skip=1; next
    } else { print $0 }
  }
}
" "$mf" > "$mf.__tmp__1"

# 2) Strip removed names from any .PHONY lines
sed -E '
  /^\.[Pp][Hh][Oo][Nn][Yy]:/{
    s/\<seed-layer2-all\>//g;
    s/\<seed-layer2-all-fresh\>//g;
    s/\<seed-all\>//g;
    s/\<seed-layer1-all\>//g;
    s/\<clear-layer-stamps\>//g;
    s/\<zap-layer-stamps\>//g;
    s/\<seed-layer-all\>//g;
    s/[[:space:]]+/ /g; s/: +/: /;
  }
' "$mf.__tmp__1" > "$mf.__tmp__2"

# 3) Ensure check-stamps & show-stamps exist (append if missing)
need_check=1; need_show=1
grep -qE '^[[:space:]]*check-stamps:' "$mf.__tmp__2" && need_check=0 || true
grep -qE '^[[:space:]]*show-stamps:'  "$mf.__tmp__2" && need_show=0  || true

{
  cat "$mf.__tmp__2"
  if (( need_check )); then
    cat <<'MK'

.PHONY: check-stamps
check-stamps: ## check stamp files on mounted ROOT
	@root="${ROOT_MNT:-/mnt/sysclone-root}"; \
	for f in /var/lib/sysclone/first-boot.done \
	         /var/lib/sysclone/.layer2-installed \
	         /var/lib/sysclone/.layer2.5-greetd-installed; do \
	  if [ -e "$$root$$f" ]; then echo "[stamp] $$f: PRESENT"; else echo "[stamp] $$f: missing"; fi; \
	done
MK
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
  fi
} > "$mf.__tmp__3"

mv "$mf.__tmp__3" "$mf"
rm -f "$mf.__tmp__1" "$mf.__tmp__2"

echo "Done. Backup: $bak"
