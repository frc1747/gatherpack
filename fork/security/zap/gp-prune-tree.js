// ZAP standalone script (Graal.js): trim the site tree to a few records per
// kind of page before the active scan, so the attack covers every feature
// instead of every record.
//
// A crawl finds the same pages for every record a role can reach
// (141 people x 7 pages, 381 events, ...). Each attack rule runs against each
// copy, so a rule spends its time limit on repeats. Path segments that are
// record ids (NeatIds such as per_..., evt_...; plain numbers; UUIDs) are
// grouped under their parent node; the first KEEP ids keep their whole
// subtree, the rest are removed. Every other node (every route, every
// non-id segment, every method and parameter set) stays.
//
// Runs after the HAR export, so crossrole.py still gets the full crawl.

var Model = Java.type("org.parosproxy.paros.model.Model");
var LogManager = Java.type("org.apache.logging.log4j.LogManager");
var log = LogManager.getLogger("gp-prune");

var KEEP = 3;
var ID = /^(?:[a-z]{2,6}_[a-z0-9]{16,}|\d+|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/;

// Node names look like "people", "per_abc...", "GET:per_abc...(q,sort)" or
// "PATCH:per_abc...()(form_response[answers])". Strip the method and params.
function segment(name) {
  var s = String(name);
  var colon = s.indexOf(":");
  if (colon > 0 && /^[A-Z]+$/.test(s.substring(0, colon))) s = s.substring(colon + 1);
  var paren = s.indexOf("(");
  if (paren >= 0) s = s.substring(0, paren);
  // "evt_x.turbo_stream", "evt_x.json": the id is before the format.
  var dot = s.indexOf(".");
  if (dot > 0) s = s.substring(0, dot);
  return s;
}

function count(node) {
  var n = 1;
  for (var i = 0; i < node.getChildCount(); i++) n += count(node.getChildAt(i));
  return n;
}

var tree = Model.getSingleton().getSession().getSiteTree();
var before = count(tree.getRoot());
var removedIds = 0;

function prune(node) {
  var kept = {};
  var keptCount = 0;
  var drop = [];
  for (var i = 0; i < node.getChildCount(); i++) {
    var child = node.getChildAt(i);
    var seg = segment(child.getNodeName());
    if (!ID.test(seg)) continue;
    if (kept[seg]) continue;
    if (keptCount < KEEP) { kept[seg] = true; keptCount++; continue; }
    drop.push(child);
  }
  var droppedSegs = {};
  for (var j = 0; j < drop.length; j++) {
    droppedSegs[segment(drop[j].getNodeName())] = true;
    tree.removeNodeFromParent(drop[j]);
  }
  removedIds += Object.keys(droppedSegs).length;
  for (var k = 0; k < node.getChildCount(); k++) prune(node.getChildAt(k));
}

prune(tree.getRoot());
var after = count(tree.getRoot());
log.info("gp-prune - kept " + KEEP + " records per kind of page: nodes " + before + " -> " + after + ", records dropped " + removedIds);
print("gp-prune - nodes " + before + " -> " + after + ", records dropped " + removedIds);
