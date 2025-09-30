#!/usr/bin/env bash
set -Eeuo pipefail
echo "[by-path] Candidate disk paths (pick the one for your SD reader):"
ls -l /dev/disk/by-path 2>/dev/null | sed -n '1,200p' || echo "  (none)"
echo
echo "[by-id] Candidate disk IDs (fallback if by-path is empty):"
ls -l /dev/disk/by-id 2>/dev/null | sed -n '1,200p' || echo "  (none)"
