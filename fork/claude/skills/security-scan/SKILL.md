---
name: security-scan
description: Authenticated ZAP security scans of a GatherPack staging copy as several non-admin roles, the cross-role access check, the signed-out scan, code checks, and resetting staging between runs (kit in fork/security/zap). Use when asked to scan, pen-test, run ZAP, run the security campaign, or check what one role can reach of another's.
---

# Security scans of a staging copy (ZAP)

A staging copy only, never production: the deep scans really change and delete what each role can reach. The kit is `fork/security/zap/` on `hbr/platform`. Everything about the site (address, backup and restore, logs, the Rails runner, team names, ZAP location, the data folder) is in one local config file, never committed: `$GP_SCAN_CONFIG`, default `~/.config/gatherpack-scan/config.env` (template: `config.example.env`). The data folder (`SCAN_DATA`, mode 700) holds passwords, run folders and ZAP homes; a staging copy of production holds real data, so nothing from it is committed or printed.

## The kit

- `campaign.sh [--baseline <stamp>] [--code-only]`: the whole campaign (run book below).
- `run-scan.sh <role> <mode>`: one run. Modes `quick`/`full` (`plan-full.yaml`), `deep` (`plan-deep.yaml`), `deep-quick` (minutes of `deep`, to test changes); role `public` uses `plan-public.yaml` (signed out). Headless; `ZAP_WINDOW=1` opens a window, which froze in a long scan. `ZAP_SKIP_RULES="<ids>"` turns rules off (finishing a stopped run).
- `campaign-rest.sh <baseline> <done run dirs>... -- <roles>...`: the rest of a campaign unattended.
- `crossrole.py`: replays every page each role crawled as every other role and signed out; `--writes` replays their changes too (changes staging: last, restore after).
- `check-logins.py`, `setup-accounts.sh [--commit]` (`rails/scan_accounts.rb`), `rails/role_ids.rb`, `summarize-campaign.py`, `known-findings.tsv`, `known-error-locations.txt`, `watch-zap.sh [--brief]`, `queue-scans.sh <role>...`.
- ZAP scripts:
  - `gp-auth.js`: signs in by loading the Devise form and posting it with its `authenticity_token` in one session. ZAP's browser sign-in (authhelper 0.44) reported false failures and stalled; its form sign-in sent a stale token.
  - `gp-csrf-token.js`: puts the session's CSRF token on every write; without it about 75% of write attacks stop at Rails' token check. Plans must `add` then `enable` it. It takes the token from every HTML page ZAP receives (so it follows a new session after a re-sign-in), gives rules that build requests without a user the scan user's token (`borrowed`), and drops a `Referer` naming the request's own URL (a refused page redirects to its Referer; following that looped, BL-091). It never sends a request as the scan user itself: that deadlocked ZAP (its lock against the user's lock during a sign-in check). `rejected` counts every 422 page, failed saves too: judge token failures by the app log's `Can't verify CSRF` count.
  - `gp-prune-tree.js`: after the HAR export, keeps 3 records of each kind of page, so attacks cover every feature, not every record.
  - `gp-apply-filters.js`: applies the `alertFilter` job's false-alarm filters, which ZAP doesn't apply in `-cmd` runs.

## Roles (`SCAN_EMAIL_PATTERN`, none admin)

student (member of `SCAN_TEAM_MEMBER`), parent (in `SCAN_TEAM_GUARDIANS`, guardian of student), mentor (in `SCAN_TEAM_MENTORS`, manager of the student's team), student2 (in `SCAN_TEAM_PEER`, outside the mentor's team), architect (in `SCAN_TEAM_MENTORS`, architect flag, manages nothing).

## Run book

One command runs the automated campaign; run it in a terminal pane with `watch-zap.sh --brief` beside it, and don't close that pane. About 18 hours; staging ends restored to the baseline. Run it after a release reaches staging and before production, or after a change to permissions, forms or sign-in.

```bash
cd fork/security/zap        # in the hbr/platform checkout
./campaign.sh                      # fresh baseline backup, then everything
./campaign.sh --baseline <stamp>   # reuse a baseline
./campaign.sh --code-only          # code checks only, nothing on staging
```

First-time setup (once per machine, or after staging is reloaded and loses the scan logins):

1. Full (not headless) OpenJDK, ZAP 2.17 (`ZAP_SH`), its add-ons in `ZAP_HOME_DEEP` (accessControl, ascanrulesBeta, pscanrulesBeta, fileupload, wappalyzer, authstats: `zap.sh -dir <home> -cmd -addoninstall <id>`), Firefox (the browser crawl runs it headless).
2. The config file, from `config.example.env`; its four commands (baseline, restore, app logs, Rails runner) are small local scripts for your server.
3. `$SCAN_DATA/passwords.txt` (mode 600): `<role> <password>` per line. Never print it.
4. `./setup-accounts.sh` (dry run), then `--commit`: the five people, teams, guardianship and flags. Only new logins get a password: resetting one ends its sessions.
5. `python3 -I check-logins.py`: all five "signed in".

| # | Check | What it covers | Step |
|---|---|---|---|
| S0 | Preflight | ZAP present, all logins sign in, fresh `role-ids.json` | stops if a login fails |
| S1 | Baseline | `SCAN_BASELINE_CMD` | unless `--baseline` |
| S2 | Deep scan per role | every feature each non-admin role reaches: injection, XSS, redirects, CSRF, tampering, headers | one role at a time, restore after each |
| S3 | Cross-role reads | every page any role crawled, as every other role and signed out | `crossrole.py` |
| S4 | Cross-role writes | every change a role made, replayed as every other role | `crossrole.py --writes`, then restore |
| S5 | Signed-out scan | sign-in, join and public pages (last and alone: rate limits) | `run-scan.sh public deep`, then restore |
| S6 | Code | Brakeman, `bin/importmap audit`, bundler-audit in `SCAN_CODE_DIR` | `code-checks.md` |
| S7 | Summary | alerts, server errors by location, cross-role findings, code checks; anything not in the `known-*` files is **NEW** | `campaign-<ts>/summary.md` |

Afterwards: read the summary's "New" list, then cross-role `findings.md` (score 4+ first) as the role in question. Each new item becomes a backlog item (`fork-spec`) or a checked false alarm: add it to `known-findings.tsv` (and the plan's `alertFilter` if ZAP should mark it), and append reviewed error locations to `known-error-locations.txt`. Write up the campaign (bottom line, what was tested, runs, findings with BL numbers, dismissed alerts, open items) and give the owner a doc of it.

Checks the campaign can't make (MCP and OAuth, business-logic permissions, admin code, stored scripts across roles, uploads): backlog items BL-093 to BL-106, each with its staging check under Tests. Once a check is repeatable, script it under `fork/security/zap/probes/` and add a row above.

## Checks that a run is real

- First minutes: ZAP's `zap.log` (in its home) shows `gp-auth - sign-in ...: 303`; the app log shows pages, not only `/assets`, and no redirects to `/users/sign_in`.
- Attack phase: the app log's `Can't verify CSRF` stays near 0 while `NotAuthorizedError` refusals appear; `gp-csrf -` counts show `set` rising and `notoken` 0. `zap-run.log` shows `gp-prune - nodes A -> B` before it.
- Attack times per role should be similar: one far shorter than the rest (a mentor run took 49 minutes against 4.5 hours) needs explaining before it counts.
- Rules stuck at "Skipped, exceeded max rule time" mean the tree is too big. DOM XSS hits its 60-minute cap; that's accepted.
- `run-scan.sh` deletes the saved `gatherpack.policy` first: ZAP keeps it and the plan's policy job won't replace it.
- `alertFilter`: `urlRegex: true` / `evidenceRegex: true` are switches, the pattern goes in `url` / `evidence`; a bad value fails the whole plan before it starts.
- `Unrecognised ... rule ID` lines name retired rules: drop them from the plan.
- A stalled run (only health checks in the app log while ZAP runs): `kill -QUIT <ZAP pid>` writes a thread dump into `zap-run.log`; look for `Found one Java-level deadlock`. Save the findings first with `reports/action/generate` on the run's API (`api.port`, `api.key`).
- To finish a stopped run, rerun the role on a restored staging with `ZAP_SKIP_RULES` set to the rules it completed.

## Gotchas

- Sign-in check: the plan polls `/users/sign_in` every 30 requests with only `loggedOutRegex` (the form). ZAP matches bodies only, so a poll that redirects when signed out never notices a lost session.
- Never restart staging's web server during a run: the session ends and the run is worthless. Stop, restore, start over.
- Save the app's error lines before restoring (the kit does: `scan-errors.log`); they're the evidence for bad-input crashes. Keep enough app log on staging for a whole run (50 MB x 10 is enough).
- With one Puma worker the web process pegs a core and responses slow about 10x: give staging 3 workers for scans.
- `pkill -f <pattern>` matches the shell running it: find PIDs with `pgrep -f "^java .*zap-.*\.jar"` and kill those. Headless Firefox can outlive ZAP: stop leftover `firefox --marionette` by PID.
- A CDN in front of staging (Cloudflare) refuses Python's default User-Agent (error 1010): `crossrole.py` sends a Firefox one; any new script must too.
- The bundled ChromeDriver can be a version ahead of installed Chrome; the plans use Firefox.
