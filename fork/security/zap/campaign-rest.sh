#!/usr/bin/env bash
# Rest of a security campaign, unattended (procedure: security-scan skill).
# Each step saves the app's error lines into its folder, then restores the
# baseline. Stops at the first failed scan or restore.
#
#   campaign-rest.sh <baseline stamp> <prev run dir>... -- <role>...
#   e.g. campaign-rest.sh 20261125-203610-pre-zap-deep \
#          $D/2026...-student-deep $D/2026...-parent-deep -- student2 architect
#
# Order: the listed deep roles, then crossrole.py over every run's HAR, then
# crossrole.py --writes, then the public deep scan (last and alone).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
scan_need SCAN_RESTORE_CMD SCAN_APP_LOGS_CMD
D="$SCAN_DATA"
BASE="${1:?baseline stamp}"; shift
HARS=(); while [[ $# -gt 0 && "$1" != "--" ]]; do HARS+=("$1"); shift; done; shift || true
ROLES=("$@")
say() { echo "=== $(date '+%m-%d %H:%M') $*"; }

save_errors() { # <dir> <since ISO>
  scan_cmd "$SCAN_APP_LOGS_CMD" "$2" | grep -E "Error \(|app/" > "$1/scan-errors.log"
  say "saved $(wc -l < "$1/scan-errors.log") error lines to $1/scan-errors.log"
}
restore() {
  say "restoring the staging site to $BASE"
  scan_cmd "$SCAN_RESTORE_CMD" "$BASE" > "$1/restore.log" 2>&1 || { say "RESTORE FAILED ($1/restore.log); stopping"; exit 1; }
  say "restored"
}
scan() { # <role>
  local since; since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  say "starting $1 deep"
  "$SCAN_KIT_DIR/run-scan.sh" "$1" deep 2>&1 | grep --line-buffered -E "^(out:|Job .* (started|finished)|gp-prune|Automation plan)"
  local out; out=$(ls -1dt "$D"/2*-"$1"-deep | head -1)
  save_errors "$out" "$since"
  restore "$out"
  [[ -f "$out/scan-$1.json" ]] || { say "$1 FAILED (no report in $out); stopping"; exit 1; }
  HARS+=("$out")
  say "finished $1 ($out)"
}

while scan_zap_running; do say "waiting for the running ZAP"; sleep 60; done
for r in "${ROLES[@]}"; do scan "$r"; done

CR="$D/$(date +%Y%m%d-%H%M%S)-crossrole"; mkdir -m 700 -p "$CR/read" "$CR/writes"
args=(); for h in "${HARS[@]}"; do args+=(--har-dir "$h"); done
since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
say "crossrole (reads) -> $CR/read"
python3 "$SCAN_KIT_DIR/crossrole.py" "${args[@]}" --ids "$D/role-ids.json" --out "$CR/read" > "$CR/read/run.log" 2>&1 || say "crossrole reads exited $? (see run.log)"
say "crossrole --writes -> $CR/writes"
python3 "$SCAN_KIT_DIR/crossrole.py" "${args[@]}" --ids "$D/role-ids.json" --out "$CR/writes" --writes > "$CR/writes/run.log" 2>&1 || say "crossrole writes exited $? (see run.log)"
save_errors "$CR" "$since"
restore "$CR"

scan public
say "campaign done"
