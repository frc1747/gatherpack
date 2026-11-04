require "test_helper"
require_relative "../../support/mcp_world"
require_relative "../../support/mcp_page_world"

# With real connections rather than a test's shared, transaction-wrapped one: what stopping
# a render leaves behind.
class Mcp::PageRenderConnectionTest < ActiveSupport::TestCase
  include McpWorld
  include McpPageWorld

  self.use_transactional_tests = false

  cattr_accessor :backend_pid

  setup do
    @viewer = User.create!(email: "render@example.com", password: "Password1!", admin: true)
    @person = Person.create!(user: @viewer, first_name: "Render", last_name: "World")
    @original_limit = Mcp::PageRender.time_limit
    Mcp::PageRender.time_limit = 0.5
  end

  teardown do
    Mcp::PageRender.time_limit = @original_limit
    McpToolCall.where(user: @viewer).delete_all
    created = Page.where("title LIKE 'ERB %' OR title = 'Half done'")
    AuditLog.where(item_id: [ *created.pluck(:id), @person.id, @viewer.id ]).delete_all
    created.delete_all
    @person.delete
    @viewer.delete
  end

  def page_for(content)
    call_tool("get_page", user: @viewer, page_id: erb_page(content).neat_id)
  end

  def statement_timeout
    ActiveRecord::Base.lease_connection.select_value("SHOW statement_timeout")
  end

  test "a stopped query dies on the server, and its connection never returns to the pool" do
    result = page_for(<<~ERB)
      <% connection = ActiveRecord::Base.lease_connection %>
      <% Mcp::PageRenderConnectionTest.backend_pid = connection.select_value("SELECT pg_backend_pid()") %>
      <% connection.execute("SELECT pg_sleep(60)") %>
    ERB

    assert_match(/stopped/, result.error)
    gone = 50.times.any? do
      next true if ActiveRecord::Base.lease_connection.select_value("SELECT count(*) FROM pg_stat_activity WHERE pid = #{backend_pid.to_i}").zero?

      sleep 0.1
      false
    end
    assert gone, "the stopped render's backend is still there"
    assert_not_equal backend_pid, ActiveRecord::Base.lease_connection.select_value("SELECT pg_backend_pid()")
    assert_equal "0", statement_timeout
  end

  test "a stopped render's open transaction is rolled back" do
    result = page_for(<<~ERB)
      <% Page.transaction do %>
        <% Page.create!(title: "Half done", content: "x", viewer: "admin", editor: "admin") %>
        <% sleep 60 %>
      <% end %>
    ERB

    assert_match(/stopped/, result.error)
    assert_not Page.exists?(title: "Half done")
  end

  test "statement_timeout doesn't outlast the render, however it ends" do
    [ "fine", "<% raise 'no' %>", "<% exit %>", "<% raise Pundit::NotAuthorizedError %>" ].each do |content|
      page_for(content)

      connections = ActiveRecord::Base.connection_pool.connections
      assert_operator connections.size, :>=, 1
      Array.new(connections.size) { Thread.new { ActiveRecord::Base.connection_pool.with_connection { |connection| connection.select_value("SHOW statement_timeout") } }.value }
        .each { |value| assert_equal "0", value, content }
      assert_equal "0", statement_timeout
    end
  end

  test "a query the server stops is a render error, on a connection that goes on working" do
    Mcp::PageRender.time_limit = 3

    result = page_for(%(<% ActiveRecord::Base.lease_connection.execute("SET statement_timeout = 100"); ActiveRecord::Base.lease_connection.execute("SELECT pg_sleep(60)") %>))

    assert_equal "This page couldn't be rendered", result.error
    assert_equal "0", statement_timeout
  end

  test "it renders when every other connection in the pool is taken" do
    pool = ActiveRecord::Base.connection_pool
    release = Queue.new
    taken = Queue.new
    holders = Array.new(pool.size - 1) do
      Thread.new do
        pool.with_connection do |connection|
          connection.select_value("SELECT 1")
          taken << true
          release.pop
        end
      end
    end
    holders.size.times { taken.pop }
    pool.lease_connection

    assert_equal "fine", page_for("fine").value["content"]
  ensure
    holders.size.times { release << true }
    holders.each(&:join)
  end
end
