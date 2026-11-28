#!/usr/bin/env python3
"""Sign in as each ZAP scan login on the staging site and say which work (passwords never printed)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import crossrole
ROLES = crossrole.CFG["SCAN_ROLES"].split()
pw = {k: v.strip() for k, v in (l.split(None, 1) for l in open(crossrole.PASSWORDS).read().split("\n") if l.strip())}
bad = 0
for r in ROLES:
    try:
        crossrole.Session(r, crossrole.EMAIL_PATTERN % r, pw[r]); print(f"{r}: signed in")
    except SystemExit as e:
        bad += 1; print(e)
    except Exception as e:
        bad += 1; print(f"{r}: {type(e).__name__}")
sys.exit(1 if bad else 0)
