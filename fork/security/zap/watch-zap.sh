#!/usr/bin/env bash
# Live view of the newest ZAP run (run-scan.sh). Refreshes every 10 s.
# --brief: only the numbers and alerts (no run name or Job lines).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BRIEF=0; [[ "${1:-}" == "--brief" ]] && BRIEF=1
DATA="$SCAN_DATA"; BASEURL="$SCAN_BASE_URL"
while true; do
  RUN=$(ls -1dt "$DATA"/2*-full "$DATA"/2*-deep 2>/dev/null | head -1)
  clear
  (( BRIEF )) || echo "run: $(basename "$RUN")   $(date +%H:%M:%S)"
  (( BRIEF )) || grep -E "^Job .* (started|found|finished|terminated)" "$RUN/zap-run.log" 2>/dev/null | tail -6
  if [[ -f "$RUN/api.key" ]] && pgrep -f "port $(cat "$RUN/api.port")" >/dev/null; then
    API="http://127.0.0.1:$(cat "$RUN/api.port")/JSON"; K="apikey=$(cat "$RUN/api.key")"
    (( BRIEF )) || echo; echo "requests sent:  $(curl -s "$API/core/view/numberOfMessages/?baseurl=$BASEURL&$K" | jq -r .numberOfMessages)"
    echo "ajax spider:    $(curl -s "$API/ajaxSpider/view/status/?$K" | jq -r .status)"
    curl -s "$API/ascan/view/scans/?$K" | jq -r '.scans[]? | "active scan:    \(.progress)% (\(.state))"'
    id=$(curl -s "$API/ascan/view/scans/?$K" | jq -r '.scans[-1].id // empty')
    [[ -n "$id" ]] && curl -s "$API/ascan/view/scanProgress/?scanId=$id&$K" | jq -r '[.scanProgress[1].HostProcess[]?.Plugin | select(.[3]=="Running" or (.[3]|test("%")))] | .[] | "  rule: \(.[0]) \(.[3])"' | head -3
    echo; echo "alerts so far:"; curl -s "$API/alert/view/alertsSummary/?baseurl=$BASEURL&$K" | jq -r '.alertsSummary | to_entries[] | "  \(.key): \(.value)"'
    echo; echo "newest alerts:"; curl -s "$API/alert/view/alerts/?baseurl=$BASEURL&start=0&count=2000&$K" | jq -r '[.alerts[] | "  [\(.risk)] \(.alert)"] | unique | .[]' | grep -v Informational | head -12
  else
    echo; echo "(no live API for this run; console tail)"; tail -5 "$RUN/zap-run.log" 2>/dev/null | cut -c1-150
  fi
  sleep 10
done
