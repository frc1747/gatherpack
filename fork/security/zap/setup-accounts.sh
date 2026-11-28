#!/usr/bin/env bash
# Create (or update) the scan logins on the staging site with rails/scan_accounts.rb.
#   setup-accounts.sh            dry run (rolled back)
#   setup-accounts.sh --commit   write
# Passwords come from $SCAN_DATA/passwords.txt ("<role> <password>" per line,
# mode 600). They reach the runner through its environment: the runner gets
# only the bare name (SCAN_PW_STUDENT), so they never appear in `ps`. Only new
# logins get a password: resetting one ends its sessions.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
scan_need SCAN_RAILS_RUNNER_CMD SCAN_TEAM_MEMBER SCAN_TEAM_GUARDIANS SCAN_TEAM_MENTORS SCAN_TEAM_PEER SCAN_ADMIN_EMAIL
PW="$SCAN_DATA/passwords.txt"
[[ -f "$PW" ]] || scan_die "no $PW (one line per role: <role> <password>)"
args=(); [[ "${1:-}" == "--commit" ]] && args+=("COMMIT=1")
for role in student parent mentor student2 architect; do
  p="$(awk -v r="$role" '$1==r{print $2}' "$PW")"
  [[ -n "$p" ]] || scan_die "no password for $role in $PW"
  export "SCAN_PW_${role^^}=$p"; args+=("SCAN_PW_${role^^}")
done
args+=("SCAN_EMAIL_PATTERN=$SCAN_EMAIL_PATTERN" "SCAN_TEAM_MEMBER=$SCAN_TEAM_MEMBER" "SCAN_TEAM_GUARDIANS=$SCAN_TEAM_GUARDIANS"
       "SCAN_TEAM_MENTORS=$SCAN_TEAM_MENTORS" "SCAN_TEAM_PEER=$SCAN_TEAM_PEER" "SCAN_ADMIN_EMAIL=$SCAN_ADMIN_EMAIL")
scan_cmd "$SCAN_RAILS_RUNNER_CMD" "${args[@]}" "$SCAN_KIT_DIR/rails/scan_accounts.rb"
