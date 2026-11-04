require "test_helper"
require_relative "../../support/mcp_world"
require_relative "../../support/mcp_page_world"

# Over the real /mcp endpoint: get_page's params in the Rails log, at the production level.
class Mcp::PagesReadsLogTest < ActionDispatch::IntegrationTest
  include McpWorld
  include McpPageWorld

  setup do
    host! "localhost"
    build_mcp_world
  end

  def log_of(arguments)
    io = StringIO.new
    sink = ActiveSupport::Logger.new(io, level: :info)
    Rails.logger.broadcast_to(sink)
    @response_body = mcp_post(mcp_token(user(:alpha_member)), "tools/call", { name: "get_page", arguments: arguments })
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(sink)
  end

  test "a page renders over the endpoint, and its params stay out of the log, on both lines" do
    page = erb_page("Hello <%= current_user.person.first_name %>, <%= params[:term] %>")

    log = log_of({ page_id: page.neat_id, params: { term: "a-private-value" } })

    assert_includes @response_body.to_json, "Hello AlphaMember, a-private-value"
    assert_equal "ok", McpToolCall.order(:created_at).last.outcome
    assert_includes log, "Processing by McpController"
    assert_includes log, "Processing by Mcp::PageRendersController"
    assert_includes log, page.neat_id
    assert_not_includes log, "a-private-value"
  end

  test "a page's output isn't logged, and a refused call's params aren't either" do
    log = log_of({ page_id: erb_page("the output of the page").neat_id })
    assert_not_includes log, "the output of the page"

    log = log_of({ page_id: erb_page("x", viewer: "admin").neat_id, params: { term: "a-private-value" } })
    assert_includes @response_body.to_json, "Not found"
    assert_not_includes log, "a-private-value"
  end
end
