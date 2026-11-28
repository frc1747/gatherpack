#!/usr/bin/env python3
"""Cross-role access check for GatherPack on a staging copy (procedure: security-scan skill).

ZAP attacks each role's own pages but never asks "can role B open what role A
found?". This does: it takes the pages each role reached while crawling
(crawl-<role>.har from the deep scans), requests every one of them as every
role and as a signed-out visitor, and records what each got.

    crossrole.py --har-dir DIR [--har-dir DIR ...] --ids ids.json --out OUTDIR
                 [--roles student,parent,...] [--writes] [--delay 0.15]

Reads:
  --har-dir   run folders holding crawl-<role>.har
  --ids       JSON from rails/role_ids.rb (its ROLEIDS line; campaign.sh saves it)
  passwords   $SCAN_DATA/passwords.txt
Config: SCAN_BASE_URL, SCAN_DATA, SCAN_EMAIL_PATTERN (see config.example.env).
Writes (OUTDIR, mode 700, may hold real data):
  matrix.csv  one row per page: who found it, what each role got
  findings.md pages a role was served that its own crawl never reached,
              ranked by how likely they are to be a real leak
  writes.csv  with --writes: replayed changes and whether each was refused

--writes replays each role's recorded POST/PATCH/PUT/DELETE requests that
target a record as every other role. Anything not refused really changes
the site: run it last and restore the site afterwards.
"""
import argparse, csv, html, http.cookiejar, json, os, re, sys, time, urllib.error, urllib.parse, urllib.request
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scanconfig

CFG = scanconfig.load("SCAN_BASE_URL", "SCAN_DATA")
BASE = CFG["SCAN_BASE_URL"]
EMAIL_PATTERN = CFG["SCAN_EMAIL_PATTERN"]
UA = "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"
PASSWORDS = os.path.join(CFG["SCAN_DATA"], "passwords.txt")
SKIP = re.compile(r"^/(assets|rails/active_storage|users|cable|jobs|up$|service-worker|manifest|icon|favicon|robots\.txt|cdn-cgi)")
REFUSED_TEXT = "You are not allowed to do that"
NEAT = re.compile(r"\b(per|evt|frm|tm|bdg|chkl|ann|wdg|sus|ord|cmt|reg|pg)_[a-z0-9]{20,}")
PER = re.compile(r"\bper_[a-z0-9]{20,}")
META = re.compile(r'<meta name="csrf-token" content="([^"]+)"')
TITLE = re.compile(r"<title>(.*?)</title>", re.S)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


class Session:
    def __init__(self, role, email=None, password=None):
        self.role = role
        self.jar = http.cookiejar.CookieJar()
        self.follow = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar))
        self.nofollow = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar), NoRedirect)
        # Cloudflare refuses Python's default User-Agent (error 1010).
        for o in (self.follow, self.nofollow):
            o.addheaders = [("User-Agent", UA)]
        self.token = None
        if email:
            self.sign_in(email, password)

    def _open(self, opener, req):
        try:
            r = opener.open(req, timeout=60)
            return r.status, dict(r.headers), r.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            return e.code, dict(e.headers or {}), e.read().decode("utf-8", "replace") if e.fp else ""

    def sign_in(self, email, password):
        _, _, body = self._open(self.follow, urllib.request.Request(BASE + "/users/sign_in"))
        tok = re.search(r'name="authenticity_token" value="([^"]+)"', body).group(1)
        data = urllib.parse.urlencode({"authenticity_token": tok, "user[email]": email, "user[password]": password}).encode()
        status, headers, _ = self._open(self.nofollow, urllib.request.Request(BASE + "/users/sign_in", data=data))
        if status not in (302, 303) or "/users/sign_in" in headers.get("Location", ""):
            sys.exit(f"{self.role}: sign-in failed ({status})")
        self.refresh_token()

    def refresh_token(self):
        _, _, body = self._open(self.follow, urllib.request.Request(BASE + "/"))
        m = META.search(body)
        self.token = m.group(1) if m else None

    def get(self, path):
        """Returns (outcome, detail, body) for one page."""
        status, headers, body = self._open(self.nofollow, urllib.request.Request(BASE + path))
        return classify(self, status, headers, body)

    def send(self, method, path, body, content_type):
        headers = {"X-CSRF-Token": self.token or "", "Content-Type": content_type or "application/x-www-form-urlencoded",
                   "Accept": "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"}
        if body and self.token and "authenticity_token=" in body:
            body = re.sub(r"authenticity_token=[^&]*", "authenticity_token=" + urllib.parse.quote(self.token, safe=""), body)
        req = urllib.request.Request(BASE + path, data=(body or "").encode(), method=method, headers=headers)
        status, rheaders, rbody = self._open(self.nofollow, req)
        return classify(self, status, rheaders, rbody)


def classify(sess, status, headers, body):
    loc = headers.get("Location", "")
    if status == 200:
        m = TITLE.search(body)
        return "served", html.unescape(m.group(1).strip())[:80] if m else "", body
    if status in (301, 302, 303):
        path = urllib.parse.urlparse(loc).path
        if path.startswith("/users/sign_in"):
            return "sign-in", "", ""
        # Pundit refusals redirect back with a flash: read it on the next page.
        _, _, next_body = sess._open(sess.follow, urllib.request.Request(loc if loc.startswith("http") else BASE + loc))
        if REFUSED_TEXT in next_body:
            return "refused", "", ""
        return "redirect", path, ""
    if status == 404:
        return "not-found", "", ""
    if status == 422:
        return "rejected-422", "", ""
    if status >= 500:
        return "error", str(status), ""
    return f"http-{status}", "", ""


def har_entries(path):
    with open(path) as f:
        return json.load(f)["log"]["entries"]


def load_crawls(dirs, roles):
    pages = defaultdict(set)    # path -> roles that reached it with a 200 page
    writes = defaultdict(list)  # role -> recorded changes aimed at a record
    for d in dirs:
        for name in os.listdir(d):
            m = re.match(r"crawl-(.+)\.har$", name)
            if not m or (roles and m.group(1) not in roles):
                continue
            role = m.group(1)
            for e in har_entries(os.path.join(d, name)):
                req, res = e["request"], e["response"]
                u = urllib.parse.urlparse(req["url"])
                if u.netloc != urllib.parse.urlparse(BASE).netloc or SKIP.match(u.path):
                    continue
                path = u.path + ("?" + u.query if u.query else "")
                ctype = next((h["value"] for h in res.get("headers", []) if h["name"].lower() == "content-type"), "")
                if req["method"] == "GET" and res["status"] == 200 and "html" in ctype:
                    pages[path].add(role)
                elif req["method"] in ("POST", "PATCH", "PUT", "DELETE") and NEAT.search(u.path):
                    post = req.get("postData") or {}
                    writes[role].append((req["method"], path, post.get("text", ""), post.get("mimeType", "")))
    return pages, writes


def collapse(pages, per_path=3):
    """Keep at most a few query variants of each page (ransack filters)."""
    out, seen = {}, defaultdict(int)
    for path in sorted(pages, key=lambda p: (("?" in p), p)):
        base = path.split("?")[0]
        if seen[base] < per_path:
            seen[base] += 1
            out[path] = pages[path]
    return out


def priority(role, path, outcome, ids):
    """How worrying it is that `role` was served `path` it never found itself."""
    if outcome != "served":
        return 0
    mine = ids.get(role, {})
    allowed = {mine.get("self")} | set(mine.get("wards", [])) | set(mine.get("managed", []))
    people = set(PER.findall(path))
    score = 1
    if people - allowed:
        score += 3  # someone else's person record
    if re.search(r"/(edit|new)\b", path):
        score += 2  # a form that changes things
    if role == "anonymous":
        score += 4
    return score


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--har-dir", action="append", required=True)
    ap.add_argument("--ids", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--roles", default="")
    ap.add_argument("--writes", action="store_true")
    ap.add_argument("--delay", type=float, default=0.15)
    a = ap.parse_args()
    roles = [r for r in a.roles.split(",") if r]
    os.makedirs(a.out, mode=0o700, exist_ok=True)
    ids = json.load(open(a.ids))
    pw = dict(l.split(None, 1) for l in open(PASSWORDS).read().split("\n") if l.strip())
    pw = {k: v.strip() for k, v in pw.items()}

    pages, writes = load_crawls(a.har_dir, roles)
    pages = collapse(pages)
    found_roles = sorted({r for rs in pages.values() for r in rs})
    who = found_roles + ["anonymous"]
    print(f"{len(pages)} pages from crawls by {', '.join(found_roles)}; checking as {', '.join(who)}", flush=True)

    sessions = {r: Session(r, EMAIL_PATTERN % r, pw[r]) for r in found_roles}
    sessions["anonymous"] = Session("anonymous")

    rows, findings = [], []
    for i, (path, finders) in enumerate(sorted(pages.items()), 1):
        row = {"page": path, "found_by": " ".join(sorted(finders))}
        for r in who:
            outcome, detail, _ = sessions[r].get(path)
            row[r] = outcome + (f" ({detail})" if detail and outcome != "served" else "")
            if r not in finders:
                score = priority(r, path, outcome, ids)
                if score:
                    findings.append((score, r, path, detail, row["found_by"]))
            time.sleep(a.delay)
        rows.append(row)
        if i % 50 == 0:
            print(f"  {i}/{len(pages)}", flush=True)

    with open(os.path.join(a.out, "matrix.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["page", "found_by"] + who)
        w.writeheader()
        w.writerows(rows)

    findings.sort(key=lambda x: (-x[0], x[1], x[2]))
    with open(os.path.join(a.out, "findings.md"), "w") as f:
        f.write("# Pages served to a role whose own crawl never reached them\n\n")
        f.write("Score: +3 another person's record (not self, ward or managed), +2 an edit/new form, +4 signed out.\n")
        f.write("A served page is not automatically a leak (shared lists, own team): read the page as that role.\n\n")
        f.write("| Score | Role | Page | Title | Found by |\n|---|---|---|---|---|\n")
        for score, r, path, title, found in findings:
            f.write(f"| {score} | {r} | `{path}` | {title} | {found} |\n")
    print(f"matrix: {len(rows)} pages; findings: {len(findings)} (score>=4: {sum(1 for x in findings if x[0] >= 4)})")

    if a.writes:
        out = []
        for owner, reqs in writes.items():
            for method, path, body, ctype in reqs[:400]:
                for r in who:
                    if r == owner:
                        continue
                    outcome, detail, _ = sessions[r].send(method, path, body, ctype)
                    out.append({"owner": owner, "as": r, "method": method, "page": path, "outcome": outcome, "detail": detail})
                    time.sleep(a.delay)
                    if outcome == "rejected-422":
                        sessions[r].refresh_token()
        with open(os.path.join(a.out, "writes.csv"), "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=["owner", "as", "method", "page", "outcome", "detail"])
            w.writeheader()
            w.writerows(out)
        accepted = [o for o in out if o["outcome"] not in ("refused", "sign-in", "not-found", "rejected-422")]
        print(f"writes: {len(out)} replayed, {len(accepted)} not refused (see writes.csv)")


if __name__ == "__main__":
    main()
