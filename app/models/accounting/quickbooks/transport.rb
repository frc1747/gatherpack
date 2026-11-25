require "net/http"

# Sends one HTTP request for Accounting::Quickbooks::Client. Tests pass a
# fake with the same #call instead.
class Accounting::Quickbooks::Transport
  # intuit_tid is Intuit's id for the exchange, which it asks for in support
  # requests. It says nothing about the data.
  Response = Struct.new(:status, :body, :intuit_tid, keyword_init: true)

  def call(method, url, headers: {}, body: nil)
    uri = URI(url)
    request = (method == :post ? Net::HTTP::Post : Net::HTTP::Get).new(uri)
    headers.each { |name, value| request[name] = value }
    request.body = body if body

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 60) do |http|
      http.request(request)
    end
    Response.new(status: response.code.to_i, body: response.body.to_s, intuit_tid: response["intuit_tid"])
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError, OpenSSL::SSL::SSLError => e
    raise Accounting::TemporaryFailure, "QuickBooks couldn't be reached (#{e.class.name.demodulize})"
  end
end
