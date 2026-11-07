# Cloudflare Turnstile as the sign-up form's challenge. It is off while the
# site key or the secret is blank: the form shows no widget and everything
# passes, so only the honeypot and minimum time (FormGuard) apply. Settings
# are read on every request, so changing them needs no restart.
#
# A submission that can't be checked (no token, a refusal, Cloudflare down or
# slow) fails, and the person is asked to try again.
class Intake::BotCheck::Turnstile
  VERIFY_URL = URI("https://challenges.cloudflare.com/turnstile/v0/siteverify")
  TOKEN_PARAM = "cf-turnstile-response"
  TIMEOUT_SECONDS = 5
  FAILURE_MESSAGE = "We couldn't check that you're a person. Please try again."

  def configured?
    site_key.present? && secret.present?
  end

  def name
    configured? ? "Cloudflare Turnstile" : "No bot check"
  end

  def partial
    "intake/bot_check/turnstile" if configured?
  end

  def site_key
    Settings[:intake_turnstile_site_key].to_s.strip
  end

  def failure_message
    FAILURE_MESSAGE
  end

  def passed?(params, request)
    return true unless configured?
    token = params[TOKEN_PARAM].to_s
    return false if token.blank?
    verified?(token, request.remote_ip)
  end

  # The one HTTP call, the seam tests replace. Returns the body, or nil on an error status.
  def post(form)
    http = Net::HTTP.new(VERIFY_URL.host, VERIFY_URL.port)
    http.use_ssl = true
    http.open_timeout = http.read_timeout = http.write_timeout = TIMEOUT_SECONDS
    response = http.post(VERIFY_URL.path, URI.encode_www_form(form))
    response.body if response.is_a?(Net::HTTPSuccess)
  end

  private

  def secret
    Settings[:intake_turnstile_secret].to_s.strip
  end

  # The secret travels only in the POST body to Cloudflare, and nothing here
  # logs it, the token or the response.
  def verified?(token, remote_ip)
    body = JSON.parse(post(secret: secret, response: token, remoteip: remote_ip).to_s)
    body["success"] == true
  rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::ProtocolError
    false
  end
end
