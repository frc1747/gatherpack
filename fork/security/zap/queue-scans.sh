#!/usr/bin/env bash
# Run scans one after another, after any scan already running.
#   queue-scans.sh parent mentor
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
while scan_zap_running; do echo "$(date +%H:%M) waiting for the running scan to finish"; sleep 60; done
for role in "$@"; do
  echo "=== $(date +%H:%M) starting $role"; "$DIR/run-scan.sh" "$role" full | grep -E "^(out:|Job .* (started|found|finished)|Automation plan)"
  out=$(ls -1dt "$SCAN_DATA"/2*-"$role"-full | head -1)
  [[ -f "$out/scan-$role.html" ]] || { echo "=== $(date +%H:%M) $role FAILED (no report in $out); stopping"; exit 1; }
  echo "=== $(date +%H:%M) finished $role"
done
