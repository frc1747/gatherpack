#!/usr/bin/env python3
"""Summarize a ZAP campaign: High/Medium alerts, server errors, cross-role findings.
Marks what known-findings.tsv already explains, so new items stand out.

  summarize-campaign.py --out summary.md RUN_DIR... [--crossrole DIR]
"""
import argparse, collections, glob, json, os, re
HERE = os.path.dirname(os.path.abspath(__file__))
SEEN_ERRORS = os.path.join(HERE, "known-error-locations.txt")  # file:line seen in earlier campaigns

def known():
    k = []
    for l in open(os.path.join(HERE, "known-findings.tsv")):
        if l.startswith("#") or not l.strip(): continue
        kind, rx, verdict = l.rstrip("\n").split("\t")
        k.append((kind, re.compile(rx), verdict))
    return k

def verdict(K, kind, text):
    for k, rx, v in K:
        if k == kind and rx.search(text): return v
    return None

def errors(path):
    c, cur = collections.Counter(), {}
    for line in open(path, errors="replace"):
        m = re.match(r"\[([0-9a-f-]{36})\] ([A-Z][\w:]+) \(", line)
        if m: cur[m.group(1)] = m.group(2); continue
        m = re.match(r"\[([0-9a-f-]{36})\] (app/[^:]+:\d+)", line)
        if m and m.group(1) in cur: c[(cur.pop(m.group(1)), m.group(2))] += 1
    for cls in cur.values(): c[(cls, "")] += 1
    return c

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("runs", nargs="+"); ap.add_argument("--crossrole"); ap.add_argument("--out", required=True)
    a = ap.parse_args(); K = known()
    seen = set(open(SEEN_ERRORS).read().split()) if os.path.exists(SEEN_ERRORS) else set()
    out = ["# Security campaign summary", ""]
    new_items = []
    out += ["## Scan alerts (High and Medium)", "", "| Run | Risk | Alert | Count | Where | Verdict |", "|---|---|---|---|---|---|"]
    for run in a.runs:
        for rep in sorted(glob.glob(os.path.join(run, "scan-*.json")) + glob.glob(os.path.join(run, "ditto-*.json"))):  # ditto-*: reports from before the kit was generic
            d = json.load(open(rep)); name = os.path.basename(run)
            for s in d["site"]:
                for al in s["alerts"]:
                    if al["riskcode"] not in ("3", "2") or al.get("confidence") == "0": continue
                    path = re.sub(r"^https?://[^/]+", "", al["instances"][0]["uri"]).split("?")[0]
                    v = verdict(K, "alert", f'{al["alert"]} {path}')
                    if not v: new_items.append(f'alert: {al["alert"]} at {path} ({name})')
                    out.append(f'| {name} | {al["riskdesc"].split(" (")[0]} | {al["alert"]} | {al["count"]} | `{path[:60]}` | {v or "**NEW: check**"} |')
    out += ["", "## Server errors (by class and first app line, all runs)", "", "| Count | Error | Where | Verdict |", "|---|---|---|---|"]
    total = collections.Counter()
    for run in a.runs:
        p = os.path.join(run, "scan-errors.log")
        if not os.path.exists(p): p = os.path.join(run, "ditto-errors.log")  # before the kit was generic
        if os.path.exists(p): total += errors(p)
    for (cls, where), n in total.most_common():
        v = verdict(K, "error", f"{cls} {where}")
        if v and v.startswith("BL-087") and where and where not in seen:
            v = "**NEW location: check** (else add to BL-087)"; new_items.append(f"error: {cls} at {where} ({n})")
        elif not v:
            v = "**NEW: check**"; new_items.append(f"error: {cls} at {where} ({n})")
        out.append(f"| {n} | {cls} | `{where}` | {v} |")
    if a.crossrole:
        out += ["", "## Cross-role check", ""]
        for part in ("read", "writes"):
            f = os.path.join(a.crossrole, part, "findings.md")
            if os.path.exists(f):
                body = open(f).read().splitlines()
                out += [f"### {part}: {f}", ""] + body[:40] + ([f"... ({len(body)-40} more lines)"] if len(body) > 40 else []) + [""]
            else:
                out += [f"### {part}: no findings.md (see {a.crossrole}/{part}/run.log)", ""]; new_items.append(f"crossrole {part} produced no findings.md")
    out[2:2] = ["## New since the last campaign", ""] + ([f"- {x}" for x in new_items] or ["- nothing"]) + [""]
    open(a.out, "w").write("\n".join(out) + "\n"); os.chmod(a.out, 0o600)
    print(f"{a.out}: {len(new_items)} new item(s)")

if __name__ == "__main__":
    main()
