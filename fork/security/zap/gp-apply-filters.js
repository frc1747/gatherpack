// ZAP standalone script (Graal.js): apply the plan's global alert filters to
// every alert raised so far. In ZAP 2.17 -cmd runs, the alertFilter job adds
// the filters but alerts are not checked against them, so the deep plan runs
// this just before writing its reports. It calls the same code as the API's
// alertFilter/action/applyGlobal (which cleared 12 alerts by hand).
var API = Java.type("org.zaproxy.zap.extension.api.API");
var JSONObject = Java.type("net.sf.json.JSONObject");
var res = API.getInstance().getImplementors().get("alertFilter").handleApiAction("applyGlobal", new JSONObject());
print("gp-apply-filters - " + res.toString());
