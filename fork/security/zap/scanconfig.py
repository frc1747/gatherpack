"""Reads the kit's local config for the Python scripts.

Values come from the environment (the shell scripts export them); anything
not set there is read from the config file ($GP_SCAN_CONFIG, default
~/.config/gatherpack-scan/config.env): KEY=VALUE lines, optional quotes,
$HOME/$VAR and ~ expanded. Command substitutions are not supported.
"""
import os, re, sys

DEFAULTS = {
    "SCAN_ROLES": "student parent mentor student2 architect",
    "SCAN_EMAIL_PATTERN": "zap.%s@example.invalid",
}


def _parse(path):
    out = {}
    for line in open(path):
        m = re.match(r"\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
        if not m:
            continue
        v = m.group(2).strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]
        elif " #" in v:
            v = v.split(" #")[0].rstrip()
        out[m.group(1)] = os.path.expanduser(os.path.expandvars(v))
        os.environ.setdefault(m.group(1), out[m.group(1)])  # later lines may use earlier ones
    return out


def load(*required):
    path = os.environ.get("GP_SCAN_CONFIG") or os.path.expanduser("~/.config/gatherpack-scan/config.env")
    if not all(os.environ.get(k) for k in required):
        if not os.path.exists(path):
            sys.exit(f"scan kit: no config file at {path} (copy config.example.env there, or set GP_SCAN_CONFIG)")
        _parse(path)
    cfg = {k: os.environ.get(k) or d for k, d in DEFAULTS.items()}
    cfg.update({k: os.environ[k] for k in os.environ if k.startswith(("SCAN_", "ZAP_"))})
    cfg["SCAN_ROLES"] = cfg.get("SCAN_ROLES") or DEFAULTS["SCAN_ROLES"]
    cfg["SCAN_EMAIL_PATTERN"] = cfg.get("SCAN_EMAIL_PATTERN") or DEFAULTS["SCAN_EMAIL_PATTERN"]
    missing = [k for k in required if not cfg.get(k)]
    if missing:
        sys.exit(f"scan kit: set {', '.join(missing)} in {path} (see config.example.env)")
    if cfg.get("SCAN_BASE_URL"):
        cfg["SCAN_BASE_URL"] = cfg["SCAN_BASE_URL"].rstrip("/")
    return cfg
