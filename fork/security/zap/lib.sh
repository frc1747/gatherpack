# Shared by every script in the kit: loads the local config and checks it.
# Source it:  source "$(dirname "$0")/lib.sh"; scan_need SCAN_BASE_URL ...
# Config file: $GP_SCAN_CONFIG, default ~/.config/gatherpack-scan/config.env
# (copy config.example.env there).

SCAN_KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN_CONFIG_FILE="${GP_SCAN_CONFIG:-$HOME/.config/gatherpack-scan/config.env}"

scan_die() { echo "scan kit: $*" >&2; exit 2; }

[[ -f "$SCAN_CONFIG_FILE" ]] || scan_die "no config file at $SCAN_CONFIG_FILE (copy $SCAN_KIT_DIR/config.example.env there, or set GP_SCAN_CONFIG)"
set -a
# shellcheck disable=SC1090
source "$SCAN_CONFIG_FILE"
set +a

: "${SCAN_ROLES:=student parent mentor student2 architect}"
: "${SCAN_EMAIL_PATTERN:=zap.%s@example.invalid}"
SCAN_BASE_URL="${SCAN_BASE_URL%/}"
export SCAN_KIT_DIR SCAN_ROLES SCAN_EMAIL_PATTERN SCAN_BASE_URL
export GP_SCAN_CONFIG="$SCAN_CONFIG_FILE"

# scan_need VAR...: stop with a clear message when a variable is not set.
scan_need() {
  local v missing=()
  for v in "$@"; do [[ -n "${!v:-}" ]] || missing+=("$v"); done
  (( ${#missing[@]} == 0 )) || scan_die "set ${missing[*]} in $SCAN_CONFIG_FILE (see $SCAN_KIT_DIR/config.example.env)"
}

scan_need SCAN_BASE_URL SCAN_DATA
export SCAN_DATA

# What the plans and ZAP scripts need from the base URL: a regex for the
# plans (escaped once, then doubled for YAML double quotes) and the host name.
SCAN_URL_RE="$(printf '%s' "$SCAN_BASE_URL" | sed -e 's/[][\.*^$?+(){}|]/\\&/g' -e 's/\\/\\\\/g')"
_hostport="${SCAN_BASE_URL#*://}"; _hostport="${_hostport%%/*}"
SCAN_HOST="${_hostport%%:*}"
export SCAN_URL_RE SCAN_HOST

# scan_email <role>: the role's sign-in email.
# shellcheck disable=SC2059
scan_email() { printf "$SCAN_EMAIL_PATTERN" "$1"; }

# scan_cmd "<command>" [args...]: run a config command with extra arguments
# appended, stdin closed.
scan_cmd() {
  local c="$1"; shift
  bash -c "$c \"\$@\"" scan-cmd "$@" < /dev/null
}

# scan_zap_running: true while a ZAP process is running.
scan_zap_running() { pgrep -f "^java .*zap-[0-9.]+\.jar" >/dev/null; }
