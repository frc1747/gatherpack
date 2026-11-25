require "test_helper"
require_relative "../../support/mcp_world"

class Mcp::CallLogMaskingTest < ActiveSupport::TestCase
  include McpWorld

  class Masked < Mcp::Tool
    tool_name "test_masked"
    description "Masked"
    scope :read
    mask_argument :clue, with: ->(value) { "#{value.first(2)}••" }
    mask_argument :plain
    mask_argument :broken, with: ->(_value) { raise "can't mask" }
    input_schema(properties: { clue: { type: "string" }, plain: { type: "string" }, broken: { type: "string" }, open: { type: "string" } })

    def call(**) = {}
  end

  setup { build_mcp_world }

  def last_arguments
    McpToolCall.where(tool: "test_masked").order(:created_at).last.arguments
  end

  test "a declared argument is stored masked, and the others as given" do
    with_tool(Masked) { call_tool("test_masked", user: user(:admin), clue: "1234567", plain: "hidden", open: "shown") }

    assert_equal({ "clue" => "12••", "plain" => Mcp::Tool::MASKED, "open" => "shown" }, last_arguments)
  end

  test "a refused call is stored masked too" do
    with_tool(Masked) { call_tool("test_masked", user: user(:admin), plain: "hidden", clue: 7) }

    assert_not_includes last_arguments.to_json, "hidden"
  end

  test "a call the server answers without running the tool is stored masked too" do
    Mcp::CallLog.record(ctx: mcp_context(user(:admin)), tool: Masked, arguments: { "plain" => "hidden" },
      result: Mcp::Tool::Result.new(error: "Not available to this token", outcome: :denied))

    assert_equal({ "plain" => Mcp::Tool::MASKED }, last_arguments)
  end

  test "a mask that fails stores no arguments at all" do
    with_tool(Masked) { call_tool("test_masked", user: user(:admin), broken: "hidden", open: "shown") }

    assert_equal Mcp::CallLog::NOT_STORABLE, last_arguments
  end
end
