# Refuses oversized gateway webhook requests before Rails reads, parses or
# logs their body. GatewaysController checks the size again, for servers
# that pass a body on without a Content-Length.
class WebhookBodyLimit
  # POST /gateways/:id/webhook(.:format). Rails squeezes repeated slashes
  # before routing, so the path is squeezed here too.
  WEBHOOK_PATH = %r{\A/gateways/[^/]+/webhook(?:\.[^/]*)?/?\z}

  def initialize(app)
    @app = app
  end

  def call(env)
    if env["REQUEST_METHOD"] == "POST" && WEBHOOK_PATH.match?(env["PATH_INFO"].to_s.squeeze("/")) && env["CONTENT_LENGTH"].to_i > GatewaysController::WEBHOOK_MAX_BYTES
      [ 413, { "content-type" => "text/plain" }, [ "Request body too large." ] ]
    else
      @app.call(env)
    end
  end
end

Rails.application.config.middleware.insert_before Rack::MethodOverride, WebhookBodyLimit
