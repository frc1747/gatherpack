// ZAP HTTP sender script (Graal.js): give every state-changing request to
// GatherPack a valid Rails CSRF token, so active-scan attacks reach the
// controllers instead of stopping at verify_authenticity_token (422).
//
// GatherPack pages submit most writes through Turbo, which sends the token in
// an X-CSRF-Token header taken from <meta name="csrf-token">; the forms that
// ZAP replays (button_to deletes, the shared delete modal, Turbo links with
// data-turbo-method) carry no token in the body. Rails accepts either the body
// token or the header.
//
// The token belongs to the Rails session. ZAP keeps a scan user's cookies in
// its own cookie store and attaches them only on the wire, so a script never
// sees them as a header. Every HTML page ZAP receives carries the token of the
// session that fetched it, so the script takes it from responses and caches
// it per scan user; after ZAP signs in again, the next page brings the new
// session's token. Messages without a scan user get a probe of /notifications
// with their own cookies. A 422 from the token check drops the cached token.

// The scanned host comes from the kit config (SCAN_BASE_URL), exported as
// SCAN_HOST by run-scan.sh.
var HOST = String(Java.type("java.lang.System").getenv("SCAN_HOST") || "");
if (!HOST) throw "SCAN_HOST is not set (run-scan.sh exports it from SCAN_BASE_URL)";
var COOKIE = "_gatherpack_session";
var META = /<meta name="csrf-token" content="([^"]+)"/;
var tokens = {};      // scan user (or session cookie) -> token
var counts = {set: 0, fetched: 0, harvested: 0, borrowed: 0, selfref: 0, nocookie: 0, notoken: 0, rejected: 0};
var reported = 0;

function sessionValue(cookieHeader) {
  if (!cookieHeader) return null;
  var m = new RegExp("(?:^|;\\s*)" + COOKIE + "=([^;]+)").exec(cookieHeader);
  return m ? m[1] : null;
}

var HttpMessage = Java.type("org.parosproxy.paros.network.HttpMessage");
var URI = Java.type("org.apache.commons.httpclient.URI");
var LOG = Java.type("org.apache.logging.log4j.LogManager").getLogger("gp-csrf");

// A GET of /notifications with the request's own cookies (no scan user).
function probeFor(msg) {
  var probe = new HttpMessage(new URI("https://" + HOST + "/notifications", true));
  var cookie = msg.getRequestHeader().getHeader("Cookie");
  if (cookie) probe.getRequestHeader().setHeader("Cookie", cookie);
  return probe;
}

// Cache key: the scan user, or the session cookie for messages without one.
function keyFor(msg) {
  var user = msg.getRequestingUser();
  if (user) return "user:" + user.getName();
  var v = sessionValue(msg.getRequestHeader().getHeader("Cookie"));
  return v ? "cookie:" + v : null;
}

function fetchToken(probe, helper) {
  try {
    helper.getHttpSender().sendAndReceive(probe, false);
    var m = META.exec(probe.getResponseBody().toString());
    counts.fetched++;
    return m ? m[1] : null;
  } catch (e) {
    LOG.warn("token fetch failed: " + e);
    return null;
  }
}

function report() {
  var total = counts.set + counts.nocookie + counts.notoken;
  if (total - reported >= 200 || total == 1) {
    reported = total;
    LOG.info(JSON.stringify(counts));
  }
}

function sendingRequest(msg, initiator, helper) {
  var h = msg.getRequestHeader();
  if (h.getURI().getHost() != HOST) return;
  // A refused page redirects back to its Referer (redirect_back_or_to). ZAP
  // follows redirects and keeps the Referer, so a page that names itself as
  // its Referer redirects to itself until ZAP gives up: a scan once
  // spent its time on such loops (about 1 attack a second). Drop
  // a Referer that is the request's own URL; the refusal then goes home.
  var ref = h.getHeader("Referer");
  if (ref && ref == h.getURI().toString()) { h.setHeader("Referer", null); counts.selfref++; }
  var method = h.getMethod();
  if (method == "GET" || method == "HEAD" || method == "OPTIONS") return;
  var path = h.getURI().getPath();
  if (path && path.indexOf("/users/") == 0) return;
  var key = keyFor(msg);
  if (!key) { counts.nocookie++; report(); return; }
  var token = tokens[key];
  // Scan rules that build their own messages (SQL injection, httpoxy) send
  // them without a scan user, but the active scan's sender still puts the
  // scan user's cookies on the wire after this script runs. Their own Cookie
  // header is then a stale copy from the crawl, and a token keyed by it was
  // rejected (about 1 in 8 of their writes in one run). A scan has one
  // user: give these messages that user's token.
  if (!msg.getRequestingUser()) {
    var userKeys = Object.keys(tokens).filter(function (k) { return k.indexOf("user:") == 0; });
    if (userKeys.length == 1) { token = tokens[userKeys[0]]; counts.borrowed++; }
  }
  // Probe only for messages without a scan user. Sending as the scan user
  // from inside this script deadlocked ZAP once: the script holds its
  // own lock while ZAP's sign-in check needs the user's lock, and the check's
  // poll comes back through this script. A scan user's token comes from the
  // pages ZAP receives (responseReceived), which start before any write.
  if (!token && !msg.getRequestingUser()) {
    token = fetchToken(probeFor(msg), helper);
    if (token) tokens[key] = token;
  }
  if (token) { h.setHeader("X-CSRF-Token", token); counts.set++; }
  else counts.notoken++;
  report();
}

function responseReceived(msg, initiator, helper) {
  var h = msg.getRequestHeader();
  if (h.getURI().getHost() != HOST) return;
  var status = msg.getResponseHeader().getStatusCode();
  if (status == 200 && msg.getResponseHeader().isHtml()) {
    var found = META.exec(msg.getResponseBody().toString());
    var k = found ? keyFor(msg) : null;
    if (k && tokens[k] != found[1]) { tokens[k] = found[1]; counts.harvested++; }
  }
  if (msg.getResponseHeader().getStatusCode() == 422 &&
      msg.getResponseBody().toString().indexOf("change you wanted was rejected") >= 0) {
    counts.rejected++;
    var key = keyFor(msg);
    if (key) delete tokens[key];
    if (counts.rejected % 50 == 1) {
      var u = msg.getRequestingUser();
      var sv = sessionValue(h.getHeader("Cookie"));
      LOG.info("422 on " + h.getMethod() + " " + h.getURI().getPath() + " user=" + (u ? u.getName() : "none") +
        " cookie=" + (sv ? sv.substring(0, 12) : "none") + " initiator=" + initiator + " " + JSON.stringify(counts));
    }
  }
}
