#!/usr/bin/env bash
# The whole security campaign in one command (procedure: security-scan skill).
#
#   campaign.sh                    fresh baseline backup, then everything
#   campaign.sh --baseline <stamp> reuse a baseline (e.g. 20261125-203610-pre-zap-deep)
#   campaign.sh --code-only        just the code checks and nothing on the server
#
# Steps: preflight (ZAP, logins, role ids) -> baseline backup -> five deep role
# scans -> cross-role reads + writes -> signed-out scan (each followed by a
# restore) -> code checks (Brakeman, importmap audit, bundler-audit) ->
# summary.md with anything new marked. Takes about 18 hours; run it in a
# terminal pane with watch-zap.sh --brief beside it. The staging site ends
# restored to the baseline.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
Z="$SCAN_KIT_DIR"
D="$SCAN_DATA"
ROLES=($SCAN_ROLES)
say() { echo "=== $(date '+%m-%d %H:%M') $*"; }
BASE=""; CODE_ONLY=0
while [[ $# -gt 0 ]]; do case "$1" in
  --baseline) BASE="$2"; shift 2 ;; --code-only) CODE_ONLY=1; shift ;;
  *) echo "unknown option $1"; exit 2 ;; esac; done
if (( CODE_ONLY )); then scan_need SCAN_CODE_DIR; else
  scan_need SCAN_CODE_DIR SCAN_BASELINE_CMD SCAN_RESTORE_CMD SCAN_APP_LOGS_CMD SCAN_RAILS_RUNNER_CMD ZAP_SH ZAP_HOME_DEEP ZAP_HOME_FULL
fi
INTEG="$SCAN_CODE_DIR"
mkdir -m 700 -p "$D"
C="$D/campaign-$(date +%Y%m%d-%H%M%S)"; mkdir -m 700 -p "$C"
exec > >(tee -a "$C/campaign.log") 2>&1
say "campaign folder $C"

code_checks() {
  say "code checks on $INTEG ($(git -C "$INTEG" rev-parse --short HEAD))"
  { echo "## Code checks ($(git -C "$INTEG" rev-parse --short HEAD))"; echo
    echo '### Brakeman'; echo '```'; (cd "$INTEG" && bin/brakeman --no-pager -q 2>&1 | tail -n 40); echo '```'
    echo '### importmap audit'; echo '```'; (cd "$INTEG" && bin/importmap audit 2>&1 | tail -n 30); echo '```'
    command -v bundle-audit >/dev/null || gem install --user-install bundler-audit >/dev/null
    echo '### bundler-audit'; echo '```'; (cd "$INTEG" && bundle-audit update >/dev/null 2>&1; bundle-audit check 2>&1 | tail -n 40); echo '```'
  } > "$C/code-checks.md"
  say "code checks -> $C/code-checks.md"
}
if (( CODE_ONLY )); then code_checks; exit 0; fi

# Preflight
scan_zap_running && { say "a ZAP scan is already running; stopping"; exit 1; }
[[ -x "$ZAP_SH" ]] || { say "ZAP not installed ($ZAP_SH)"; exit 1; }
python3 -I "$Z/check-logins.py" || { say "a scan login failed: run setup-accounts.sh --commit (security-scan skill)"; exit 1; }
say "role ids"
scan_cmd "$SCAN_RAILS_RUNNER_CMD" "SCAN_ROLES=$SCAN_ROLES" "SCAN_EMAIL_PATTERN=$SCAN_EMAIL_PATTERN" "$Z/rails/role_ids.rb" \
  | sed -n 's/^ROLEIDS //p' > "$C/role-ids.json.new" && [[ -s "$C/role-ids.json.new" ]] \
  && mv "$C/role-ids.json.new" "$D/role-ids.json" || { say "role ids failed"; exit 1; }

# Baseline
if [[ -z "$BASE" ]]; then
  say "baseline backup"
  BASE=$(scan_cmd "$SCAN_BASELINE_CMD" | tail -n 1) && [[ -n "$BASE" ]] || { say "backup failed; stopping"; exit 1; }
  say "baseline $BASE"
fi
echo "$BASE" > "$C/baseline"

# Scans, cross-role, public (each restores after itself)
"$Z/campaign-rest.sh" "$BASE" -- "${ROLES[@]}" || { say "campaign stopped early (see above)"; }
code_checks

# Summary
runs=(); for r in "${ROLES[@]}" public; do d=$(ls -1dt "$D"/2*-"$r"-deep 2>/dev/null | head -1); [[ -n "$d" && "$d" -nt "$C" ]] && runs+=("$d"); done
cr=$(ls -1dt "$D"/2*-crossrole 2>/dev/null | head -1)
python3 -I "$Z/summarize-campaign.py" --out "$C/summary.md" "${runs[@]}" ${cr:+--crossrole "$cr"}
cat "$C/code-checks.md" >> "$C/summary.md"
say "done: $C/summary.md"
