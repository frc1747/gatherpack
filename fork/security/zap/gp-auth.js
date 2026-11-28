// ZAP authentication script (Graal.js) for GatherPack's Devise sign-in.
// Loads the sign-in page, takes its authenticity_token and posts the form in
// the same session, so Rails' CSRF check passes. ZAP's built-in form and
// browser sign-ins both failed against GatherPack (stale token; false "failed").
//
// Parameters: base (e.g. https://staging.example.org). Credentials: username,
// password.

var HttpRequestHeader = Java.type("org.parosproxy.paros.network.HttpRequestHeader");
var HttpHeader = Java.type("org.parosproxy.paros.network.HttpHeader");
var URI = Java.type("org.apache.commons.httpclient.URI");
var URLEncoder = Java.type("java.net.URLEncoder");
var LOG = Java.type("org.apache.logging.log4j.LogManager").getLogger("gp-auth");

function enc(s) {
  return URLEncoder.encode(String(s), "UTF-8");
}

function authenticate(helper, paramsValues, credentials) {
  var base = paramsValues.get("base");
  var page = helper.prepareMessage();
  page.setRequestHeader(new HttpRequestHeader(HttpRequestHeader.GET, new URI(base + "/users/sign_in", false), HttpHeader.HTTP11));
  helper.sendAndReceive(page, false);
  var m = /name="authenticity_token" value="([^"]+)"/.exec(page.getResponseBody().toString());
  if (!m) LOG.warn("no authenticity_token on the sign-in page");

  var post = helper.prepareMessage();
  post.setRequestHeader(new HttpRequestHeader(HttpRequestHeader.POST, new URI(base + "/users/sign_in", false), HttpHeader.HTTP11));
  post.getRequestHeader().setHeader("Content-Type", "application/x-www-form-urlencoded");
  post.setRequestBody("authenticity_token=" + enc(m ? m[1] : "") +
    "&user%5Bemail%5D=" + enc(credentials.getParam("username")) +
    "&user%5Bpassword%5D=" + enc(credentials.getParam("password")));
  post.getRequestHeader().setContentLength(post.getRequestBody().length());
  helper.sendAndReceive(post, false);
  LOG.info("sign-in " + credentials.getParam("username") + ": " + post.getResponseHeader().getStatusCode() +
    " " + (post.getResponseHeader().getHeader("Location") || ""));
  return post;
}

function getRequiredParamsNames() {
  return ["base"];
}

function getOptionalParamsNames() {
  return [];
}

function getCredentialsParamsNames() {
  return ["username", "password"];
}
