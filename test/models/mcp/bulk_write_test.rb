require "test_helper"
require_relative "../../support/mcp_world"

# Mcp::Tool's bulk support, through a tool of its own: sets a bio on every person in
# a team, skipping those the viewer can't update, as a real bulk tool would skip.
class Mcp::BulkWriteTest < ActiveSupport::TestCase
  include McpWorld

  class SetBios < Mcp::Tool
    tool_name "test_set_bios"
    description "Set bios"
    scope :write
    bulk
    input_schema(properties: { bio: { type: "string" }, dry_run: dry_run_property }, required: %w[bio])
    output_schema(bulk_output_schema(REF_SCHEMA))

    def self.people = @people
    def self.people=(people)
      @people = people
    end

    def call(bio:, dry_run: false)
      bulk_write(self.class.people, dry_run: dry_run, check: ->(person) { ctx.authorize!(person, :update?) }, json: ->(person) { person_json(person) }) do |person|
        raise "boom" if bio == "boom" && person.first_name == "Second"
        if bio == "unsaved" && person.first_name == "Second"
          person.errors.add(:base, "Can't save this one")
          next false
        end

        person.update(bio: bio)
      end
    end
  end

  setup do
    build_mcp_world
    @first = person(:alpha_member)
    @second = person(:ward)
    @second.update!(first_name: "Second")
    @elsewhere = person(:beta_member)
    SetBios.people = [ @first, @second, @elsewhere ]
  end

  def run_bulk(viewer, **arguments)
    with_tool(SetBios) { call_tool("test_set_bios", user: user(viewer), **arguments) }
  end

  def last_call
    McpToolCall.where(tool: "test_set_bios").order(:created_at).last
  end

  test "it changes what the viewer may, lists the rest with reasons, and logs one row with every changed record" do
    result = nil
    assert_difference("McpToolCall.count", 1) { result = run_bulk(:alpha_manager, bio: "New") }

    assert_equal [ @first.neat_id, @second.neat_id ], result.value["changed"].map { |item| item["id"] }
    assert_equal [ { "id" => @elsewhere.neat_id, "reason" => "Not allowed" } ], result.value["skipped"]
    assert_equal false, result.value["dry_run"]
    assert_equal "New", @first.reload.bio
    assert_nil @elsewhere.reload.bio

    assert_nil last_call.changed_type
    assert_nil last_call.changed_id
    assert_equal [ { "type" => "Person", "id" => @first.id }, { "type" => "Person", "id" => @second.id } ], last_call.changed_records
    assert_equal "ok", last_call.outcome
  end

  test "a dry run changes nothing, lists the same records as a real run, and logs an empty list" do
    audit_rows = AuditLog.count
    dry = run_bulk(:alpha_manager, bio: "New", dry_run: true)

    assert_nil @first.reload.bio
    assert_equal audit_rows, AuditLog.count
    assert_equal true, dry.value["dry_run"]
    assert_empty last_call.changed_records
    assert_nil last_call.changed_type
    assert_equal true, last_call.arguments["dry_run"]

    real = run_bulk(:alpha_manager, bio: "New", dry_run: false)
    assert_equal dry.value.except("dry_run"), real.value.except("dry_run")
  end

  # ctx.allowed? answers false rather than raising, so a false check has to skip.
  test "a check that returns false or nil skips the record, dry run or not" do
    [ ->(tool, person) { tool.ctx.allowed?(person, :update?) }, ->(_tool, _person) { nil } ].each do |rule|
      tool = Class.new(Mcp::Tool) do
        tool_name "test_condition_check"
        description "Checks with a condition"
        scope :write
        bulk
        input_schema(properties: { dry_run: dry_run_property })
        define_method(:call) do |dry_run: false|
          bulk_write(SetBios.people, dry_run: dry_run, check: ->(person) { rule.call(self, person) }, json: ->(person) { person_json(person) }) { |person| person.update(bio: "Written") }
        end
      end

      [ true, false ].each do |dry_run|
        result = with_settings(mcp_write_enabled: "true") { tool.run(mcp_context(user(:guardian), scopes: "mcp_write"), dry_run: dry_run) }

        assert_empty result.value["changed"]
        assert_equal [ "Not allowed" ], result.value["skipped"].map { |item| item["reason"] }.uniq
        assert_equal 3, result.value["skipped"].size
        assert_empty result.changed_records
      end
      assert_nil @elsewhere.reload.bio
    end
  end

  test "a check using ctx.allowed? lets through what it allows" do
    tool = Class.new(Mcp::Tool) do
      tool_name "test_allowed_check"
      description "Checks with ctx.allowed?"
      scope :write
      bulk
      input_schema(properties: { dry_run: dry_run_property })
      define_method(:call) do |dry_run: false|
        bulk_write(SetBios.people, dry_run: dry_run, check: ->(person) { ctx.allowed?(person, :update?) }, json: ->(person) { person_json(person) }) { |person| person.update(bio: "Written") }
      end
    end

    result = with_settings(mcp_write_enabled: "true") { tool.run(mcp_context(user(:alpha_manager), scopes: "mcp_write"), {}) }

    assert_equal [ @first.neat_id, @second.neat_id ], result.value["changed"].map { |item| item["id"] }
    assert_equal [ { "id" => @elsewhere.neat_id, "reason" => "Not allowed" } ], result.value["skipped"]
    assert_nil @elsewhere.reload.bio
  end

  test "dry_run takes only a boolean" do
    %w[no true].each do |value|
      assert_predicate run_bulk(:admin, bio: "New", dry_run: value), :error?
      assert_nil @first.reload.bio
    end
  end

  test "exactly the limit goes through and one more refuses the whole call, dry run or not" do
    SetBios.people = Array.new(Mcp::Tool::BULK_LIMIT) { @first }
    assert_equal Mcp::Tool::BULK_LIMIT, run_bulk(:admin, bio: "New", dry_run: true).value["changed"].size

    SetBios.people = Array.new(Mcp::Tool::BULK_LIMIT + 1) { @first }
    [ true, false ].each do |dry_run|
      result = run_bulk(:admin, bio: "Over", dry_run: dry_run)
      assert_match(/201 records.*at most 200/, result.error)
      assert_empty last_call.changed_records
      assert_nil @first.reload.bio
    end
  end

  test "records the viewer can't change don't count toward the limit" do
    SetBios.people = Array.new(Mcp::Tool::BULK_LIMIT + 1) { @elsewhere } + [ @first ]

    result = run_bulk(:alpha_manager, bio: "New")

    assert_equal 1, result.value["changed"].size
    assert_equal Mcp::Tool::BULK_LIMIT + 1, result.value["skipped"].size
  end

  test "a record that fails to save is skipped with why, and the others go ahead" do
    result = run_bulk(:admin, bio: "unsaved")

    assert_equal [ { "id" => @second.neat_id, "reason" => "Can't save this one" } ], result.value["skipped"]
    assert_equal [ @first.neat_id, @elsewhere.neat_id ], result.value["changed"].map { |item| item["id"] }
    assert_equal [ @first.id, @elsewhere.id ], last_call.changed_records.map { |record| record["id"] }
  end

  test "an unexpected failure on one record is skipped as an internal error, and the others go ahead" do
    result = run_bulk(:admin, bio: "boom")

    assert_nil result.error
    assert_equal [ @first.neat_id, @elsewhere.neat_id ], result.value["changed"].map { |item| item["id"] }
    assert_equal [ { "id" => @second.neat_id, "reason" => "Internal error" } ], result.value["skipped"]
    assert_equal "boom", @first.reload.bio
    assert_equal "boom", @elsewhere.reload.bio
    assert_nil @second.reload.bio
    assert_equal [ @first.id, @elsewhere.id ], last_call.changed_records.map { |record| record["id"] }
    assert_equal "ok", last_call.outcome
    assert_equal "1 record failed unexpectedly", last_call.error_message
  end

  test "a call where every record fails unexpectedly says how many, with an empty list" do
    Hook.create!(name: "MCP test hook", event: "people - update", code: "raise 'hook failed'")

    result = run_bulk(:admin, bio: "Hooked")

    assert_empty result.value["changed"]
    assert_equal 3, result.value["skipped"].size
    assert_empty last_call.changed_records
    assert_equal "ok", last_call.outcome
    assert_equal "3 records failed unexpectedly", last_call.error_message
  end

  test "skips that aren't unexpected leave no note" do
    run_bulk(:alpha_manager, bio: "New")
    assert_nil last_call.error_message

    run_bulk(:admin, bio: "unsaved")
    assert_nil last_call.error_message

    run_bulk(:admin, bio: "boom", dry_run: true)
    assert_nil last_call.error_message
  end

  test "a hook with a syntax error is skipped like any other failure, and the call gets its row" do
    Hook.create!(name: "MCP test hook", event: "people - update", code: ")(")
    McpToolCall.delete_all

    result = run_bulk(:admin, bio: "Hooked")

    assert_empty result.value["changed"]
    assert_equal 3, result.value["skipped"].size
    assert_equal [ "Internal error" ], result.value["skipped"].map { |item| item["reason"] }.uniq
    assert_equal 1, McpToolCall.count
    assert_equal "3 records failed unexpectedly", last_call.error_message
    assert_nil @first.reload.bio
  end

  test "a ScriptError on one record leaves the others changed and logged" do
    tool = Class.new(SetBios) do
      tool_name "test_set_bios_script_error"
      description "Raises a ScriptError"
      scope :write
      bulk
      input_schema(properties: { dry_run: dry_run_property })

      def call(dry_run: false)
        bulk_write(SetBios.people, dry_run: dry_run, check: ->(_person) { true }, json: ->(person) { person_json(person) }) do |person|
          raise SyntaxError, "bad hook" if person.first_name == "Second"

          person.update(bio: "Written")
        end
      end
    end

    result = with_settings(mcp_write_enabled: "true") { tool.run(mcp_context(user(:admin), scopes: "mcp_write"), {}) }
    call = McpToolCall.where(tool: "test_set_bios_script_error").sole

    assert_equal [ @first.neat_id, @elsewhere.neat_id ], result.value["changed"].map { |item| item["id"] }
    assert_equal [ { "id" => @second.neat_id, "reason" => "Internal error" } ], result.value["skipped"]
    assert_equal [ @first.id, @elsewhere.id ], call.changed_records.map { |record| record["id"] }
    assert_equal "1 record failed unexpectedly", call.error_message
  end

  test "a ScriptError in a single-record tool is an internal error with a log row" do
    tool = Class.new(Mcp::Tool) do
      tool_name "test_script_error"
      description "Raises a ScriptError"
      scope :read

      def call = raise(SyntaxError, "bad hook")
    end

    result = tool.run(mcp_context(user(:admin)), {})

    assert_equal "Internal error", result.error
    assert_equal "error", McpToolCall.where(tool: "test_script_error").sole.outcome
  end

  test "a hook with a syntax error on a single write rolls back, and the call gets its row" do
    Hook.create!(name: "MCP test hook", event: "people - update", code: ")(")
    person(:ward).update_column(:bio, "Before")

    assert_difference("McpToolCall.where(tool: 'update_person').count", 1) do
      assert_equal "Internal error", call_tool("update_person", user: user(:admin), person_id: person(:ward).neat_id, bio: "Changed").error
    end
    assert_equal "Before", person(:ward).reload.bio
    assert_equal "error", McpToolCall.where(tool: "update_person").order(:created_at).last.outcome
  end

  test "a hook that raises on one record leaves that record unsaved, and the others go ahead" do
    Hook.create!(name: "MCP test hook", event: "people - update", code: "raise 'hook failed' if model.first_name == 'Second'")

    result = run_bulk(:admin, bio: "Hooked")

    assert_equal [ { "id" => @second.neat_id, "reason" => "Internal error" } ], result.value["skipped"]
    assert_nil @second.reload.bio
    assert_equal "Hooked", @elsewhere.reload.bio
  end

  test "a mistake in the tool isn't swallowed as a skip, and what changed is still logged" do
    tool = Class.new(SetBios) do
      tool_name "test_set_bios_bug"
      description "Has a bug"
      scope :write
      bulk
      input_schema(properties: { bio: { type: "string" }, dry_run: dry_run_property }, required: %w[bio])

      def call(bio:, dry_run: false)
        bulk_write(SetBios.people, dry_run: dry_run, check: ->(_person) { true }, json: ->(person) { person_json(person) }) do |person|
          raise Mcp::ToolBug, "a bug" if person.first_name == "Second"

          person.update(bio: bio)
        end
      end
    end

    assert_raises(Mcp::ToolBug) { with_settings(mcp_write_enabled: "true") { tool.run(mcp_context(user(:admin), scopes: "mcp_write"), bio: "New") } }
    assert_equal [ @first.id ], McpToolCall.where(tool: "test_set_bios_bug").last.changed_records.map { |record| record["id"] }
  end

  test "a write that returns false with no errors still gives a reason" do
    tool = Class.new(SetBios) do
      tool_name "test_set_bios_false"
      description "Returns false"
      scope :write
      bulk
      input_schema(properties: { dry_run: dry_run_property })

      def call(dry_run: false)
        bulk_write(SetBios.people.first(1), dry_run: dry_run, check: ->(_person) { true }, json: ->(person) { person_json(person) }) { false }
      end
    end

    result = with_settings(mcp_write_enabled: "true") { tool.run(mcp_context(user(:admin), scopes: "mcp_write"), {}) }

    assert_equal "Not saved", result.value["skipped"].sole["reason"]
    assert_empty result.value["changed"]
  end

  # Each a tool that would have written with no permission check, or during a dry run.
  {
    "no check" => ->(people, dry_run, writer) { writer.send(:bulk_write, people, dry_run: dry_run, json: :neat_id.to_proc) { |person| person.update(bio: "Written") } },
    "no dry_run" => ->(people, _dry_run, writer) { writer.send(:bulk_write, people, check: ->(_person) { true }, json: :neat_id.to_proc) { |person| person.update(bio: "Written") } }
  }.each do |name, body|
    test "a tool leaving out bulk_write's #{name} fails and writes nothing" do
      tool = Class.new(Mcp::Tool) do
        tool_name "test_unsafe_bulk"
        description "Unsafe"
        scope :write
        bulk
        input_schema(properties: { dry_run: dry_run_property })
        define_method(:call) { |dry_run: false| body.call(SetBios.people, dry_run, self) }
      end

      result = with_settings(mcp_write_enabled: "true") { tool.run(mcp_context(user(:guardian), scopes: "mcp_write"), dry_run: true) }

      assert_equal "Internal error", result.error
      assert_nil @elsewhere.reload.bio
      assert_empty result.changed_records
    end
  end

  test "a tool passing bulk_write a nil check or dry_run is a bug" do
    [ { dry_run: nil, check: ->(_person) { true } }, { dry_run: true, check: nil } ].each do |options|
      tool = Class.new(Mcp::Tool) do
        tool_name "test_nil_bulk"
        description "Nil"
        scope :write
        bulk
        input_schema(properties: { dry_run: dry_run_property })
        define_method(:call) { |**| bulk_write(SetBios.people, json: :neat_id.to_proc, **options) { |person| person.update(bio: "Written") } }
      end

      assert_raises(Mcp::ToolBug) { with_settings(mcp_write_enabled: "true") { tool.run(mcp_context(user(:admin), scopes: "mcp_write"), {}) } }
      assert_nil @first.reload.bio
    end
  end

  test "a tool that hasn't declared bulk can't use it, and a bulk tool must take dry_run" do
    tool = Class.new(Mcp::Tool) do
      tool_name "test_not_bulk"
      description "Not bulk"
      scope :write
      def call = bulk_write([], json: :itself.to_proc, dry_run: false, check: ->(_record) { })
    end
    with_settings(mcp_write_enabled: "true") do
      assert_raises(Mcp::ToolBug) { tool.run(mcp_context(user(:admin), scopes: "mcp_write"), {}) }
    end

    no_dry_run = Class.new(Mcp::Tool) do
      tool_name "test_no_dry_run"
      description "No dry run"
      scope :write
      bulk
    end
    assert_raises(ArgumentError) { Mcp.register_tool(no_dry_run) }
  end
end
