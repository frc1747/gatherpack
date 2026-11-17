require "rack/mock_request"

# Renders a Page as get_page returns it: dispatches a GET to Mcp::PageRendersController,
# a PagesController#show with the token's user, and turns the HTML into text.
#
# What differs from a browser's GET: no session, cookies, flash or real client (reading
# them finds nothing; writing the session fails the render). request.host is the app's
# ROOT_URL host, not the client's. params are the query string a browser would send. Page
# permission logic that reads current_user, policy or policy_scope runs as usual.
#
# Stopping a slow render: Timeout.timeout in the request's thread can raise in the middle
# of database work and leave that thread's connection unusable for whatever comes next.
# So the render runs in its own thread with its own connection, and the request's thread
# gives its connection back first, so that a full pool can't make the two wait for each
# other. At the limit the thread is killed, which also stops a plain Ruby loop or a sleep.
# As it unwinds, Rails rolls back any open transaction (transaction.rb checks for an
# aborting thread), and the connection is closed, not returned to the pool, as it may
# still be waiting on a query. statement_timeout stops such a query on the server, since
# closing the connection alone wouldn't. Writes the page has already committed stay.
# That covers the primary database; the versions database only sees short audit writes.
class Mcp::PageRender
  # The inner action logs its own Parameters line. Its values are the client's params,
  # which filter_parameters hides on the /mcp line, so they're hidden on this one too.
  LOGGED_PARAMETER_FILTER = [ /./ ].freeze
  # How long the converted text may be, and how much HTML to convert to get there.
  # Parsing holds the VM's lock, so the time limit can't stop it: this bounds it instead.
  MAX_TEXT_BYTES = 200.kilobytes
  MAX_HTML_BYTES = 2.megabytes
  # How long to wait for a killed thread, which may be finishing its rollback.
  KILL_GRACE_SECONDS = 1

  Rendered = Data.define(:text, :truncated)

  class_attribute :time_limit, default: 10

  def initialize(ctx, page, params)
    @ctx = ctx
    @page = page
    @params = params
  end

  # Raises Mcp::Error (or a subclass), with a message that's safe for the client.
  def call
    ActiveRecord::Base.connection_handler.clear_active_connections!(:all)
    outcome = nil
    thread = Thread.new do
      Thread.current.report_on_exception = false
      outcome = render_outcome
    end
    finished = ActiveSupport::Dependencies.interlock.permit_concurrent_loads { thread.join(time_limit) }
    unless finished
      thread.kill
      thread.join(KILL_GRACE_SECONDS)
      raise Mcp::Error, "This page took longer than #{time_limit} seconds to render and was stopped"
    end

    outcome.is_a?(Rendered) ? outcome : raise(outcome)
  end

  private

  attr_reader :ctx, :page, :params

  # A Rendered, or the Mcp::Error to raise. Exception, as this is the top of a thread and
  # a page's ERB can raise anything (SystemStackError, SystemExit). The log has the class
  # and backtrace but not the message, which can quote a param (Integer(params[:x])), and
  # the cause's class, as a template wraps what its code raises.
  def render_outcome
    Rails.application.executor.wrap do
      ctx.in_request { limiting_statements { convert(dispatch) } }
    ensure
      discard_connections if Thread.current.status == "aborting"
    end
  rescue Mcp::Error => e
    e
  rescue ActionController::BadRequest
    Mcp::InvalidArgument.new("params aren't a valid query string")
  rescue ActiveRecord::RecordNotFound
    Mcp::NotFound.new
  rescue Exception => e
    Rails.logger.error("[MCP] get_page failed on #{page.neat_id} (request #{ctx.request_id}): #{(e.cause || e).class}\n#{e.backtrace&.first(10)&.join("\n")}")
    Mcp::Error.new("This page couldn't be rendered")
  end

  def limiting_statements
    connection = ActiveRecord::Base.lease_connection
    connection.execute("SET statement_timeout = #{(time_limit * 1000).ceil}")
    yield
  ensure
    reset_statement_timeout(connection) if connection && Thread.current.status != "aborting"
  end

  # A connection that can't do this (its transaction failed, say) goes no further.
  def reset_statement_timeout(connection)
    connection.execute("RESET statement_timeout")
  rescue ActiveRecord::ActiveRecordError
    discard(connection)
  end

  def discard_connections
    ActiveRecord::Base.connection_handler.connection_pool_list(:all).each do |pool|
      connection = pool.active_connection?
      discard(connection) if connection
    end
  end

  # A pinned connection is a transactional test's, shared with the test's own thread.
  def discard(connection)
    connection.throw_away! unless connection.pinned
  end

  def dispatch
    status, _headers, body = Mcp::PageRendersController.action(:show).call(request_env)
    html = +""
    body.each { |part| html << part }
    body.close if body.respond_to?(:close)

    case status
    when 200 then html
    when 403 then raise Mcp::NotAllowed
    else raise Mcp::Error, "This page couldn't be rendered"
    end
  end

  def request_env
    url = Rails.application.routes.url_helpers.page_url(page)
    url += "?#{URI.encode_www_form(params)}" if params.present?
    Rack::MockRequest.env_for(url).merge(Rails.application.env_config).merge(
      "action_dispatch.request.path_parameters" => { controller: "pages", action: "show", id: page.to_param },
      "action_dispatch.parameter_filter" => LOGGED_PARAMETER_FILTER,
      Mcp::PageRendersController::USER_ENV_KEY => ctx.user
    )
  end

  def convert(html)
    html = html.force_encoding(Encoding::UTF_8)
    cut = html.bytesize > MAX_HTML_BYTES
    text = Mcp::PageText.call(cut ? html.byteslice(0, MAX_HTML_BYTES).scrub("") : html.scrub(""))
    cut ||= text.bytesize > MAX_TEXT_BYTES

    Rendered.new(text: text.bytesize > MAX_TEXT_BYTES ? text.byteslice(0, MAX_TEXT_BYTES).scrub("") : text, truncated: cut)
  end
end
