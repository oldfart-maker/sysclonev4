#!/usr/bin/env bash
set -Eeuo pipefail

f="tools/payloads/usr-local-bin/scpi"
bak="${f}.bak.$(date +%Y%m%d%H%M%S)"
cp -f "$f" "$bak"

# 1) Add a robust fallback function after 'wait_for_clock()' if missing
if ! grep -q 'fallback_set_http_date' "$f"; then
  awk '
    BEGIN{added=0}
    {print}
    /wait_for_clock\(\)\s*{/ {in=1}
    in==1 && /^\}/ {in=0}
    in==0 && added==0 && /wait_for_clock\(\)\s*\{/==0 && /need_make\(\)/ {
      # insert fallback utilities BEFORE next function (right after the first function)
      print "\n# Fallbacks when NTP is slow/unavailable"
      print "fallback_ntp() {"
      print "  if command -v busybox >/dev/null 2>&1; then"
      print "    busybox ntpd -n -q -p pool.ntp.org && return 0"
      print "  fi"
      print "  return 1"
      print "}"
      print ""
      print "fallback_set_http_date() {"
      print "  # Use a plain HTTP Date header (no TLS) to roughly set clock"
      print "  local d"
      print "  d=$(curl -fsI --max-time 8 http://google.com 2>/dev/null | awk -F\": \" /^Date:/{print $2; exit} ) || true"
      print "  if [ -n \"$d\" ]; then"
      print "    # Example: Sun, 28 Sep 2025 23:14:15 GMT"
      print "    sudo date -u -s \"$d\" >/dev/null 2>&1 || true"
      print "  fi"
      print "}"
      added=1
    }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
fi

# 2) Strengthen bootstrap_make: try NTP; if still not synced, set HTTP date; then proceed
perl -0777 -pe '
  s{
    (^\s*bootstrap_make\(\)\s*\{\s*.+?sudo\ timedatectl\ set-ntp\ true[^\n]*\n\s*sudo\ systemctl\ restart\ systemd-timesyncd[^\n]*\n\s*if\ !\ wait_for_clock; then\n\s*echo\s+"\[scpi\]\ WARN: clock may still be wrong; proceeding anyway"\n\s*fi)
  }{
    my $blk = $1;
    $blk .= "\n  # extra attempts if NTP was slow\n";
    $blk .= "  synced=\$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo no)\n";
    $blk .= "  if [ \"\$synced\" != yes ]; then\n";
    $blk .= "    echo \"[scpi] NTP not yet synced; trying busybox ntpd quick sync\";\n";
    $blk .= "    fallback_ntp || true;\n";
    $blk .= "  fi\n";
    $blk .= "  synced=\$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo no)\n";
    $blk .= "  now=\$(date -u +%s 2>/dev/null || echo 0)\n";
    $blk .= "  if [ \"\$synced\" != yes ] && [ \"\$now\" -lt 1704067200 ]; then\n";
    $blk .= "    echo \"[scpi] clock still bad; setting from HTTP Date (bootstrap)\";\n";
    $blk .= "    fallback_set_http_date || true;\n";
    $blk .= "    sudo timedatectl set-ntp true || true;\n";
    $blk .= "    sudo systemctl restart systemd-timesyncd || true;\n";
    $blk .= "  fi\n";
  }gmsx;
' -i "$f"

# 3) Ensure we preinstall certs/keyrings before first Syyu
perl -0777 -pe '
  s{
    (^\s*#\s*Update\ and\ install\s*\n\s*sudo\ pacman\ -Syyu\ --noconfirm\ --needed\ make)
  }{
    my $tail = $1;
    my $ins = "  # make sure CA roots + keyrings are present before any TLS mirror pulls\\n";
    $ins   .= "  sudo pacman -Sy --noconfirm --needed ca-certificates ca-certificates-mozilla || true\\n";
    $ins   .= "  sudo pacman -Sy --noconfirm --needed archlinux-keyring manjaro-keyring archlinuxarm-keyring manjaro-arm-keyring || true\\n";
    $ins   .= "  # refresh mirrors on ARM/Manjaro (best-effort)\\n";
    $ins   .= "  command -v pacman-mirrors >/dev/null 2>&1 && sudo pacman-mirrors --fasttrack 5 --geoip || true\\n";
    $ins   .= "\\n$tail";
    $ins;
  }gmsx;
' -i "$f"

echo "[harden-scpi] updated $f (backup at $bak)"
