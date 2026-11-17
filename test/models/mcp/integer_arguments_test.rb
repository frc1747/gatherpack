require "test_helper"
require_relative "../../support/mcp_world"

# Mcp::Tool's argument handling, for any integer argument: a non-finite number is a
# refusal, not "Internal error", and the tool doesn't run. Range is each schema's own.
class Mcp::IntegerArgumentsTest < ActiveSupport::TestCase
  include McpWorld

  class Counts < Mcp::Tool
    tool_name "test_counts"
    description "Counts"
    scope :read
    input_schema(properties: {
      plain: { type: "integer" },
      capped: { type: "integer", minimum: 1, maximum: 10 },
      nullable: { type: %w[integer null] },
      many: { type: "array", items: { type: "integer" } },
      nested: { type: "object", properties: { count: { type: "integer" } } },
      text: { type: %w[string integer] }
    })

    def call(**arguments) = { received: arguments.keys.map(&:to_s) }
  end

  setup { build_mcp_world }

  def counts(**arguments)
    with_tool(Counts) { call_tool("test_counts", user: user(:admin), **arguments) }
  end

  test "a non-finite number is an invalid argument, on any integer argument" do
    [ 1e400, -1e400 ].each do |number|
      { plain: number, capped: number, nullable: number, text: number }.each do |name, value|
        result = counts(name => value)
        assert_equal "#{name} is out of range", result.error, "#{name}: #{number}"
        assert_equal "error", McpToolCall.order(:created_at).last.outcome
      end
    end
  end

  test "a large finite number is left to the schema: refused with a maximum, passed on without one" do
    [ 1e30, 2**31, -(2**31), 2**70, 3_000_000_000 ].each do |number|
      assert_equal %w[plain], counts(plain: number).value["received"], number
      assert_equal %w[nullable], counts(nullable: number).value["received"], number
      assert_equal %w[text], counts(text: number).value["received"], number
      assert_predicate counts(capped: number), :error?, number
      assert_not_equal "Internal error", counts(capped: number).error, number
    end
  end

  test "a core limit still refuses large numbers through its maximum" do
    [ 1e30, 2**31, 2**70 ].each do |number|
      result = call_tool("search_people", user: user(:admin), query: "a", limit: number)
      assert_match(/greater than/, result.error, number)
    end
  end

  test "it reaches integers inside lists and objects" do
    assert_equal "many is out of range", counts(many: [ 1, 1e400 ]).error
    assert_equal "count is out of range", counts(nested: { count: 1e400 }).error
  end

  test "ordinary numbers still reach the schema check and the tool" do
    assert_equal %w[plain], counts(plain: -2).value["received"]
    assert_equal %w[plain], counts(plain: 7.0).value["received"]
    assert_equal %w[nullable], counts(nullable: nil).value["received"]
    assert_match(/not an integer/, counts(plain: 7.5).error)
    assert_match(/greater than/, counts(capped: 11).error)
  end

  test "an infinity where no integer is declared is a refusal too" do
    assert_predicate counts(many: 1e400), :error?
    assert_not_equal "Internal error", counts(many: 1e400).error
    assert_not_equal "Internal error", counts(nested: 1e400).error
  end

  test "the call log can store the call" do
    counts(plain: 1e400)

    assert_equal "test_counts", McpToolCall.order(:created_at).last.tool
    assert_not_equal Mcp::CallLog::NOT_STORABLE, McpToolCall.order(:created_at).last.arguments
  end

  if defined?(Mcp::Tools::SetPersonField)
    test "a whole number the page stores in an integer person field isn't refused" do
      person(:ward).update!(birthday: 30.years.ago.to_date)
      field = PersonField.create!(name: "Member Number", key: "member_number", data_type: :integer,
        read_permission: "everyone", write_permission: "self_and_leaders")

      with_feature(:person_fields) do
        result = call_tool("set_person_field", user: user(:admin), person_id: person(:ward).neat_id, field_key: field.key, value: 3_000_000_000)

        assert_nil result.error
        assert_equal 3_000_000_000, person(:ward).reload.field_value(field)
        assert_equal "value is out of range",
          call_tool("set_person_field", user: user(:admin), person_id: person(:ward).neat_id, field_key: field.key, value: 1e400).error
      end
    end
  end
end
