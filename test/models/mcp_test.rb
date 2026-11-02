require "test_helper"
require_relative "../support/mcp_world"

class McpTest < ActiveSupport::TestCase
  include McpWorld

  setup { build_mcp_world }

  def tool_class(name, feature: nil, scope: :read)
    Class.new(Mcp::Tool) do
      tool_name name
      description "Test tool"
      scope scope
      feature feature if feature
      define_method(:call) { { ok: true } }
    end
  end

  test "registers core tools in order and finds them by name" do
    assert_equal %w[whoami search_people], Mcp.tools.map(&:tool_name).first(2)
    assert_equal Mcp::Tools::Whoami, Mcp.tool("whoami")
    assert_equal Mcp::Tools::SearchPeople, Mcp.tool(:search_people)
    assert_nil Mcp.tool("nope")
  end

  test "registering the same name twice raises" do
    assert_raises(Mcp::DuplicateTool) { Mcp.register_tool(tool_class("whoami")) }
    assert_equal Mcp::Tools::Whoami, Mcp.tool("whoami")
  end

  test "a tool without a name can't be registered" do
    assert_raises(ArgumentError) { Mcp.register_tool(Class.new(Mcp::Tool)) }
  end

  test "reset empties the registry" do
    tools = Mcp.tools
    Mcp.reset!
    assert_empty Mcp.tools
  ensure
    Mcp.reset!
    tools.each { |tool| Mcp.register_tool(tool) }
  end

  test "running to_prepare again, as a code reload does, doesn't raise and keeps the tools" do
    tools = Mcp.tools
    Rails.application.reloader.prepare!
    assert_equal tools, Mcp.tools
  end

  test "a disabled feature's tools are neither listed nor callable" do
    tool = tool_class("test_badges", feature: :badges)
    with_tool(tool) do
      ctx = mcp_context(user(:admin))
      with_feature(:badges, false) do
        assert_not_includes Mcp.available_tools(ctx), tool
        result = call_tool("test_badges", user: user(:admin))
        assert_equal "Feature off", result.error
        assert_equal :denied, result.outcome
      end
      with_feature(:badges, true) do
        assert_includes Mcp.available_tools(ctx), tool
        assert_equal({ "ok" => true }, call_tool("test_badges", user: user(:admin)).value)
      end
    end
  end

  test "write tools need the write scope and the setting" do
    tool = tool_class("test_write", scope: :write)
    with_tool(tool) do
      read = mcp_context(user(:admin), scopes: "mcp_read")
      write = mcp_context(user(:admin), scopes: "mcp_write")

      with_settings(mcp_write_enabled: "false") do
        assert_not_includes Mcp.available_tools(write), tool
        assert_equal "Writes disabled", call_tool("test_write", user: user(:admin), scopes: "mcp_write").error
      end
      with_settings(mcp_write_enabled: "true") do
        assert_not_includes Mcp.available_tools(read), tool
        assert_includes Mcp.available_tools(write), tool
        assert_equal "Not allowed", call_tool("test_write", user: user(:admin), scopes: "mcp_read").error
      end
    end
  end

  test "mcp_write grants read tools" do
    assert_includes Mcp.available_tools(mcp_context(user(:admin), scopes: "mcp_write")), Mcp::Tools::Whoami
  end

  test "feature_registered? looks at the features registry" do
    assert Mcp.feature_registered?(:badges)
    assert_not Mcp.feature_registered?(:nope)
  end

  test "find_by_neat_id refuses another model's prefix and malformed IDs" do
    badge = @access_badge
    assert_equal badge, Mcp.find_by_neat_id(Badge, badge.neat_id)
    assert_nil Mcp.find_by_neat_id(Team, badge.neat_id)
    assert_nil Mcp.find_by_neat_id(Badge, "bdg_!!!")
    assert_nil Mcp.find_by_neat_id(Badge, "nonsense")
    assert_nil Mcp.find_by_neat_id(Badge, nil)
    assert_nil Mcp.find_by_neat_id(Badge.none, badge.neat_id)
  end

  test "an unexpected exception is logged and returned as Internal error" do
    tool = Class.new(Mcp::Tool) do
      tool_name "test_boom"
      description "Test tool"
      define_method(:call) { raise "secret detail" }
    end
    with_tool(tool) do
      result = call_tool("test_boom", user: user(:admin))
      assert_equal "Internal error", result.error
      assert_equal "error", McpToolCall.order(:created_at).last.outcome
      assert_not_includes McpToolCall.order(:created_at).last.error_message, "secret"
    end
  end

  test "Pundit's refusal becomes Not allowed" do
    target = person(:beta_member)
    tool = Class.new(Mcp::Tool) do
      tool_name "test_authorize"
      description "Test tool"
      define_method(:call) { ctx.authorize!(target, :show?) }
    end
    with_tool(tool) do
      result = call_tool("test_authorize", user: user(:alpha_member))
      assert_equal "Not allowed", result.error
      assert_equal :denied, result.outcome
    end
  end

  test "arguments are validated against the input schema and logged" do
    assert_match(/Missing required arguments: query/, call_tool("search_people", user: user(:admin)).error)
    assert_match(/Invalid arguments/, call_tool("search_people", user: user(:admin), query: "a", limit: 0).error)

    log = McpToolCall.order(:created_at).last
    assert_equal "search_people", log.tool
    assert_equal({ "query" => "a", "limit" => 0 }, log.arguments)
    assert_equal "error", log.outcome
  end
end
