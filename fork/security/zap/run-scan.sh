#!/usr/bin/env bash
# Authenticated ZAP scan of the staging site as one scan account.
#   run-scan.sh <role> [quick|full|deep|deep-quick]
#   quick/full: plan-full.yaml (first pass); deep: plan-deep.yaml (tuned
#   policy, CSRF tokens, crawl HAR for the cross-role check; long);
#   role "public": plan-public.yaml (signed out).
# Accounts: rails/scan_accounts.rb (setup-accounts.sh); passwords in
# $SCAN_DATA/passwords.txt. Reports hold the site's data (possibly real PII):
# they go to $SCAN_DATA/<time>-<role>-<mode>/ (mode 700).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
scan_need ZAP_SH ZAP_HOME_DEEP ZAP_HOME_FULL
ROLE="${1:?role}"; MODE="${2:-full}"
DATA="$SCAN_DATA"
export ZAP_ROLE="$ROLE" ZAP_EMAIL; ZAP_EMAIL="$(scan_email "$ROLE")"
ZAP_PW="$(awk -v r="$ROLE" '$1==r{print $2}' "$DATA/passwords.txt" 2>/dev/null || true)"; export ZAP_PW
[[ -n "$ZAP_PW" || "$ROLE" == public ]] || { echo "no password for $ROLE in $DATA/passwords.txt" >&2; exit 2; }
PLAN=plan-full.yaml; HOMEDIR="$ZAP_HOME_FULL"
case "$MODE" in
  quick) export ZAP_SPIDER_MIN=1 ZAP_AJAX_MIN=1 ZAP_ASCAN_MIN=1 ;;
  full)  export ZAP_SPIDER_MIN=10 ZAP_AJAX_MIN=15 ZAP_ASCAN_MIN=90 ;;
  deep)  export ZAP_SPIDER_MIN=20 ZAP_AJAX_MIN=30 ZAP_ASCAN_MIN=600
         PLAN=plan-deep.yaml; HOMEDIR="$ZAP_HOME_DEEP" ;;
  deep-quick) export ZAP_SPIDER_MIN=1 ZAP_AJAX_MIN=2 ZAP_ASCAN_MIN=3
         PLAN=plan-deep.yaml; HOMEDIR="$ZAP_HOME_DEEP" ;;
  *) echo "mode: quick|full|deep|deep-quick" >&2; exit 2 ;;
esac
[[ "$ROLE" == public ]] && PLAN=plan-public.yaml
[[ -x "$ZAP_SH" ]] || scan_die "ZAP_SH is not executable: $ZAP_SH"
umask 077
export ZAP_OUT="$DATA/$(date +%Y%m%d-%H%M%S)-$ROLE-$MODE"
mkdir -m 700 -p "$DATA" "$ZAP_OUT" "$HOMEDIR"
# ZAP keeps a scan policy once created and the activeScan-policy job won't
# replace it ("already exists"): remove it so the plan's policy applies.
rm -f "$HOMEDIR/policies/gatherpack.policy"
cd "$ZAP_OUT"
echo "out: $ZAP_OUT"
# Live API on localhost for watch-zap.sh: a port per role, a fresh key per run.
case "$ROLE" in student) PORT=8099 ;; parent) PORT=8100 ;; mentor) PORT=8101 ;; student2) PORT=8103 ;; architect) PORT=8104 ;; public) PORT=8105 ;; *) PORT=8102 ;; esac
openssl rand -hex 16 > api.key; echo "$PORT" > api.port
# ZAP only substitutes env vars after validating numbers, so fill the plan in here.
envsubst '$SCAN_BASE_URL $SCAN_URL_RE $SCAN_KIT_DIR $ZAP_ROLE $ZAP_EMAIL $ZAP_PW $ZAP_OUT $ZAP_SPIDER_MIN $ZAP_AJAX_MIN $ZAP_ASCAN_MIN' \
  < "$SCAN_KIT_DIR/$PLAN" > plan.yaml
trap 'rm -f "$ZAP_OUT/plan.yaml"' EXIT
# ZAP_SKIP_RULES="6 20019 ...": switch those attack rules off, to finish a run
# that stopped partway (the rules it completed stay off). Notes it in the log.
if [[ -n "${ZAP_SKIP_RULES:-}" ]]; then
  python3 - plan.yaml $ZAP_SKIP_RULES <<'PY'
import re, sys
path, ids = sys.argv[1], sys.argv[2:]
lines = open(path).read().split("\n")
out, anchor = [], None
for line in lines:
    m = re.match(r"(\s*)- \{id: (\d+),", line)
    if m and m.group(2) in ids:
        continue
    out.append(line)
    if line.strip() == "rules:" and anchor is None and any("policyDefinition" in l for l in out[-5:]):
        anchor = len(out)
        ind = re.match(r"(\s*)", line).group(1) + "  "
assert anchor, "policy rules: not found"
out[anchor:anchor] = [f'{ind}- {{id: {i}, threshold: "off"}}   # ZAP_SKIP_RULES' for i in ids]
open(path, "w").write("\n".join(out))
PY
  echo "skipping rules: $ZAP_SKIP_RULES"
fi
# Headless by default (the desktop window froze during a long scan); set
# ZAP_WINDOW=1 to watch in a ZAP window. The session is saved under session/
# so it can be reopened afterwards in ZAP (File > Open Session).
mkdir -p session
UI=(-cmd); [[ "${ZAP_WINDOW:-}" == 1 ]] && UI=()
# Terminal multiplexer panes don't inherit the desktop session: use GNOME's Xwayland display.
if [[ -z "${UI[*]}" && -z "${DISPLAY:-}" ]]; then
  export DISPLAY=:0 XAUTHORITY; XAUTHORITY="$(ls -t /run/user/$(id -u)/.mutter-Xwaylandauth.* 2>/dev/null | head -1)"
fi
"$ZAP_SH" "${UI[@]}" -dir "$HOMEDIR" -port "$PORT" -newsession "$ZAP_OUT/session/scan-$ROLE" \
  -config api.key="$(cat api.key)" -config api.disablekey=false -autorun "$ZAP_OUT/plan.yaml" 2>&1 | tee zap-run.log
