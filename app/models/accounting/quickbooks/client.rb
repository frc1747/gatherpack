# Talks to QuickBooks Online for one gateway: sign-in tokens, reads, change
# data capture, and billing's three writes.
#
# QuickBooks' only scope lets an app write anything, so the limits are
# enforced here: every request goes through #request, which allows exactly
#   - GET to this company's API path;
#   - POST to this company's invoice and customer endpoints whose body has
#     no Id or SyncToken and whose query has no operation, so it's a create,
#     never an update, void or delete, always with a requestid;
#   - POST to send an invoice that a billing line of this gateway created;
#   - POST to Intuit's token and revoke endpoints;
# and raises NotAllowed before anything is sent otherwise. The creates and
# the send are refused too unless the gateway's "Let GatherPack create
# invoices" is on. Nothing changes, voids or deletes a QuickBooks record,
# or records a payment.
class Accounting::Quickbooks::Client
  # A request outside what GatherPack may do in QuickBooks.
  class NotAllowed < StandardError; end

  # QuickBooks refused a request for a reason that won't go away by itself.
  class Error < StandardError
    attr_reader :status, :code

    def initialize(message, status: nil, code: nil)
      super(message)
      @status = status
      @code = code
    end
  end

  PAGE_SIZE = 1000
  # Refresh the access token when less than this is left of it.
  REFRESH_MARGIN = 5.minutes
  # QuickBooks' error code for a record that doesn't exist (any more).
  NOT_FOUND_CODE = "610".freeze

  class << self
    attr_writer :transport

    def transport
      @transport || Accounting::Quickbooks::Transport.new
    end
  end

  attr_reader :gateway

  def initialize(gateway, transport: self.class.transport)
    @gateway = gateway
    @transport = transport
  end

  # Where to send a person to sign in to QuickBooks and allow GatherPack.
  def authorize_url(state:, redirect_uri:)
    query = { client_id: gateway.client_id, response_type: "code", scope: Accounting::Quickbooks::SCOPE,
              redirect_uri: redirect_uri, state: state }
    "#{Accounting::Quickbooks::AUTHORIZE_URL}?#{query.to_query}"
  end

  # Swaps the code from the sign-in redirect for tokens and saves them.
  def exchange_code(code, redirect_uri:)
    response = token_request(grant_type: "authorization_code", code: code, redirect_uri: redirect_uri)
    raise Error.new("QuickBooks refused the sign-in (#{error_message(response)})", status: response.status) unless response.status == 200

    credential = gateway.accounting_credential || gateway.build_accounting_credential
    save_tokens(credential, JSON.parse(response.body))
  end

  # Tells Intuit to forget the tokens. Returns whether it accepted.
  def revoke!
    credential = gateway.accounting_credential
    token = credential&.refresh_token.presence || credential&.access_token
    return false if token.blank?

    response = request(:post, Accounting::Quickbooks::REVOKE_URL, body: { token: token }.to_json,
      headers: basic_auth_headers.merge("Content-Type" => "application/json", "Accept" => "application/json"))
    response.status == 200
  end

  # A current access token, refreshed first when it's about to run out.
  def access_token
    credential = gateway.accounting_credential or raise Accounting::ReconnectNeeded, "QuickBooks isn't connected"
    credential.access_token_expires_within?(REFRESH_MARGIN) ? refresh!(credential.access_token) : credential.access_token
  end

  # Refreshes the access token, unless another process already did since
  # stale_token was read. Inside a lock on the credentials row, after
  # reading it again: two jobs refreshing at once would rotate the refresh
  # token twice and lose one.
  def refresh!(stale_token = nil)
    credential = gateway.accounting_credential or raise Accounting::ReconnectNeeded, "QuickBooks isn't connected"
    refused = nil

    token = credential.with_lock do
      if credential.access_token.present? && credential.access_token != stale_token && !credential.access_token_expires_within?(REFRESH_MARGIN)
        credential.access_token
      else
        response = token_request(grant_type: "refresh_token", refresh_token: credential.refresh_token)
        case response.status
        when 200 then save_tokens(credential, JSON.parse(response.body)).access_token
        when 400, 401 then refused = error_message(response)
        else temporary_or_error!(response, "refreshing the sign-in")
        end
      end
    end

    if refused
      gateway.needs_reconnect!("QuickBooks refused to renew the sign-in (#{refused}). Reconnect QuickBooks.")
      raise Accounting::ReconnectNeeded, refused
    end
    token
  end

  # GET an API path under this company, e.g. "companyinfo/123". Returns the
  # parsed body.
  def get_json(path, params = {})
    token = access_token
    response = api_get(path, params, token)
    if response.status == 401
      response = api_get(path, params, refresh!(token))
      if response.status == 401
        gateway.needs_reconnect!("QuickBooks refused GatherPack's sign-in. Reconnect QuickBooks.")
        raise Accounting::ReconnectNeeded, "QuickBooks refused the access token"
      end
    end
    return JSON.parse(response.body) if response.status == 200

    temporary_or_error!(response, "reading #{path.split('/').first}")
  end

  # One record, or nil when QuickBooks doesn't have it (any more).
  def get(entity_type, id)
    params = entity_type == "Invoice" ? { include: "invoiceLink" } : {}
    get_json("#{entity_type.downcase}/#{id}", params)[entity_type]
  rescue Error => e
    raise unless e.code == NOT_FOUND_CODE

    nil
  end

  # Yields every row of a query, a page of PAGE_SIZE at a time.
  def query(entity_type, where: nil)
    position = 1
    loop do
      statement = "select * from #{entity_type}#{" where #{where}" if where} STARTPOSITION #{position} MAXRESULTS #{PAGE_SIZE}"
      params = { query: statement }
      params[:include] = "invoiceLink" if entity_type == "Invoice"
      rows = Array(get_json("query", params).dig("QueryResponse", entity_type))
      rows.each { |row| yield row }
      break if rows.size < PAGE_SIZE

      position += PAGE_SIZE
    end
  end

  # Yields [entity_type, row, deleted?] for each record of the types changed
  # since the time (change data capture, up to 30 days back).
  def changes(entity_types, since)
    body = get_json("cdc", entities: entity_types.join(","), changedSince: since.utc.iso8601)
    Array(body["CDCResponse"]).each do |response|
      Array(response["QueryResponse"]).each do |result|
        entity_types.each do |entity_type|
          Array(result[entity_type]).each { |row| yield entity_type, row, row["status"] == "Deleted" }
        end
      end
    end
  end

  def company_info
    get_json("companyinfo/#{gateway.realm_id}")["CompanyInfo"]
  end

  # Creates an invoice. QuickBooks returns the first invoice again when
  # the same request_id is sent twice. Returns the invoice.
  def create_invoice(body, request_id:)
    create("invoice", body, request_id)["Invoice"]
  end

  # Creates a customer, as create_invoice does. Returns the customer.
  def create_customer(body, request_id:)
    create("customer", body, request_id)["Customer"]
  end

  # Emails an invoice a billing line created from QuickBooks.
  def send_invoice(id, email:)
    writing_allowed!
    post_json("invoice/#{id}/send", { sendTo: email }, nil, content_type: "application/octet-stream", doing: "emailing the invoice")["Invoice"]
  end

  # The one way a request leaves this class. Raises NotAllowed, before
  # anything is sent, for a request GatherPack may not make.
  def request(method, url, headers: {}, body: nil)
    check_allowed!(method, url, body)
    @transport.call(method, url, headers: headers, body: body)
  end

  private
    def api_get(path, params, token)
      response = request(:get, api_url(path, params), headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" })
      gateway.record_call!
      response
    end

    def create(entity, body, request_id)
      writing_allowed!
      raise NotAllowed, "GatherPack only creates QuickBooks records with a request id" if request_id.blank?

      post_json(entity, { requestid: request_id }, body.to_json, doing: "creating the #{entity}")
    end

    def writing_allowed!
      raise NotAllowed, "Turn on \"Let GatherPack create invoices\" to bill people from GatherPack" unless gateway.allow_create_charges?
    end

    # POSTs to an API path under this company, refreshing the sign-in once
    # on a 401 as reads do. Returns the parsed body.
    def post_json(path, params, body, doing:, content_type: "application/json")
      token = access_token
      response = api_post(path, params, body, token, content_type)
      if response.status == 401
        response = api_post(path, params, body, refresh!(token), content_type)
        if response.status == 401
          gateway.needs_reconnect!("QuickBooks refused GatherPack's sign-in. Reconnect QuickBooks.")
          raise Accounting::ReconnectNeeded, "QuickBooks refused the access token"
        end
      end
      return JSON.parse(response.body) if response.status == 200

      temporary_or_error!(response, doing)
    end

    def api_post(path, params, body, token, content_type)
      response = request(:post, api_url(path, params), body: body,
        headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json", "Content-Type" => content_type })
      gateway.record_call!
      response
    end

    def check_allowed!(method, url, body = nil)
      uri = URI(url)
      allowed =
        case method
        when :get
          api_uri?(uri)
        when :post
          sign_in_post?(uri) || create_post?(uri, body) || send_post?(uri, body)
        else
          false
        end
      raise NotAllowed, "GatherPack may not #{method.to_s.upcase} #{uri.host}#{uri.path}" unless allowed
    rescue URI::InvalidURIError
      raise NotAllowed, "GatherPack may not request #{url}"
    end

    def api_uri?(uri)
      api = URI(api_host)
      gateway.realm_id.present? && uri.scheme == "https" && uri.host == api.host && uri.port == api.port &&
        uri.path.start_with?("/v3/company/#{gateway.realm_id}/")
    end

    def sign_in_post?(uri)
      uri.query.blank? && [ Accounting::Quickbooks::TOKEN_URL, Accounting::Quickbooks::REVOKE_URL ].include?("#{uri.scheme}://#{uri.host}#{uri.path}")
    end

    # A create: the invoice or customer endpoint, a requestid and nothing
    # else in the query (no operation), and a body with no Id or SyncToken.
    def create_post?(uri, body)
      return false unless gateway.allow_create_charges? && api_uri?(uri)
      return false unless [ "invoice", "customer" ].any? { |entity| uri.path == "/v3/company/#{gateway.realm_id}/#{entity}" }

      query = Rack::Utils.parse_query(uri.query)
      return false unless query["requestid"].present? && (query.keys - %w[ requestid minorversion ]).empty?

      json = JSON.parse(body.to_s)
      json.is_a?(Hash) && json.keys.none? { |key| key.to_s.downcase.in?(%w[ id synctoken sparse ]) }
    rescue JSON::ParserError
      false
    end

    # Sending an invoice that a billing line of this gateway created.
    def send_post?(uri, body)
      return false unless gateway.allow_create_charges? && api_uri?(uri) && body.blank?

      id = uri.path[%r{\A/v3/company/#{Regexp.escape(gateway.realm_id.to_s)}/invoice/([^/]+)/send\z}, 1]
      query = Rack::Utils.parse_query(uri.query)
      return false unless id && query["sendTo"].present? && (query.keys - %w[ sendTo minorversion ]).empty?

      AccountingBillingLine.created.joins(:run).where(accounting_billing_runs: { gateway_id: gateway.id }).exists?(external_id: id)
    end

    def api_host
      Accounting::Quickbooks::API_HOSTS.fetch(gateway.environment)
    end

    def api_url(path, params)
      "#{api_host}/v3/company/#{gateway.realm_id}/#{path}?#{params.merge(minorversion: Accounting::Quickbooks::MINOR_VERSION).to_query}"
    end

    def token_request(form)
      request(:post, Accounting::Quickbooks::TOKEN_URL, body: URI.encode_www_form(form),
        headers: basic_auth_headers.merge("Content-Type" => "application/x-www-form-urlencoded", "Accept" => "application/json"))
    end

    def basic_auth_headers
      { "Authorization" => "Basic #{Base64.strict_encode64("#{gateway.client_id}:#{gateway.client_secret}")}" }
    end

    # Refresh tokens rotate: the latest one must be kept.
    def save_tokens(credential, json)
      now = Time.current
      credential.access_token = json["access_token"]
      credential.access_token_expires_at = now + json["expires_in"].to_i.seconds
      credential.refresh_token = json["refresh_token"] if json["refresh_token"].present?
      credential.refresh_token_expires_at = now + json["x_refresh_token_expires_in"].to_i.seconds if json["x_refresh_token_expires_in"].present?
      credential.save!
      credential
    end

    def temporary_or_error!(response, doing)
      if response.status == 429 || response.status >= 500
        raise Accounting::TemporaryFailure, "QuickBooks answered #{response.status} while #{doing}"
      end

      raise Error.new("QuickBooks refused #{doing} (#{error_message(response)})", status: response.status, code: error_code(response))
    end

    def parsed_error(response)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      {}
    end

    def error_code(response)
      Array(parsed_error(response).dig("Fault", "Error")).first&.dig("code")&.to_s
    end

    def error_message(response)
      body = parsed_error(response)
      fault = Array(body.dig("Fault", "Error")).first
      message = fault ? [ fault["Message"], fault["Detail"] ].compact.join(": ") : body["error"]
      message.presence || "HTTP #{response.status}"
    end
end
