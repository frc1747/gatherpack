require "test_helper"
require_relative "../support/mcp_world"

class McpTest < ActiveSupport::TestCase
  include McpWorld

  # A policy that defines nothing, so every query is ApplicationPolicy's.
  class BarePolicy < ApplicationPolicy; end

  class BareRecord
    def self.policy_class
      BarePolicy
    end
  end

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

  # The lines of a method's body, without blanks and comments. Doesn't read
  # one-line defs; the policies have none.
  def method_body(method)
    file, line = method.source_location
    lines = File.readlines(file)
    closing = "#{lines[line - 1][/\A\s*/]}end"
    lines[line..].take_while { |text| text.rstrip != closing }.map(&:strip).reject { |text| text.empty? || text.start_with?("#") }
  end

  # Whether a policy query comes down to one only ApplicationPolicy implements.
  def allows_everyone?(policy, query)
    method = policy.instance_method(query)
    if method.owner == ApplicationPolicy
      delegate = Mcp::Context::DELEGATING_QUERIES[query]
      return delegate.nil? || allows_everyone?(policy, delegate)
    end

    body = method_body(method)
    forwarded = body.first&.to_sym
    body.size == 1 && body.first.match?(/\A[a-z_]+\?\z/) && policy.method_defined?(forwarded) && allows_everyone?(policy, forwarded)
  end

  # A read tool whose #call is the block, run on the tool instance.
  def read_tool(name, &block)
    Class.new(Mcp::Tool) do
      tool_name name
      description "Test tool"
      scope :read
      define_method(:call, &block)
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
    Mcp.reset!
    assert_empty Mcp.tools
  ensure
    Rails.application.reloader.prepare!
  end

  test "reset clears the person extensions" do
    Mcp.reset!
    assert_empty Mcp.person_extensions
    Mcp.person_extensions << ->(_person, _viewer) { { extra: 1 } }
    Mcp.reset!
    assert_empty Mcp.person_extensions
  ensure
    Rails.application.reloader.prepare!
  end

  test "reset clears the person filters" do
    Mcp.person_filters << ->(_person, _viewer) { [] }
    Mcp.reset!
    assert_empty Mcp.person_filters
  ensure
    Rails.application.reloader.prepare!
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
      end
      assert_equal "Writes disabled", call_tool("test_write", user: user(:admin), writes_enabled: false).error
      with_settings(mcp_write_enabled: "true") do
        assert_not_includes Mcp.available_tools(read), tool
        assert_includes Mcp.available_tools(write), tool
      end
      assert_equal "Not allowed", call_tool("test_write", user: user(:admin), scopes: "mcp_read").error
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
      scope :read
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
      scope :read
      define_method(:call) { ctx.authorize!(target, :show?) }
    end
    with_tool(tool) do
      result = call_tool("test_authorize", user: user(:alpha_member))
      assert_equal "Not allowed", result.error
      assert_equal :denied, result.outcome
    end
  end

  test "a tool must declare a scope and a description" do
    no_scope = Class.new(Mcp::Tool) do
      tool_name "test_no_scope"
      description "Test tool"
    end
    no_description = Class.new(Mcp::Tool) do
      tool_name "test_no_description"
      scope :read
    end

    assert_match(/must declare a scope/, assert_raises(ArgumentError) { Mcp.register_tool(no_scope) }.message)
    assert_match(/must declare a description/, assert_raises(ArgumentError) { Mcp.register_tool(no_description) }.message)
    assert_nil Mcp.tool("test_no_scope")
    assert_not no_scope.available?(mcp_context(user(:admin), scopes: "mcp_read mcp_write"))
  end

  # --- Context

  test "find with a model applies the policy scope" do
    ctx = mcp_context(user(:alpha_member))

    assert_equal person(:ward), ctx.find(Person, person(:ward).neat_id)
    assert_raises(Mcp::NotFound) { ctx.find(Person, person(:beta_member).neat_id) }
  end

  test "find with a model whose scope is unfiltered raises" do
    assert_raises(Mcp::ToolBug) { mcp_context(user(:admin)).find(BadgeAssignment, "bda_x") }
  end

  test "policy_scope refuses unconditional scopes unless told otherwise" do
    ctx = mcp_context(user(:alpha_member))

    assert_raises(Mcp::ToolBug) { ctx.policy_scope(Checkin) }
    assert_raises(Mcp::ToolBug) { ctx.policy_scope(BadgeAssignment) }
    assert_raises(Mcp::ToolBug) { ctx.policy_scope(person(:alpha_member).checkins) }
    assert_raises(Mcp::ToolBug) { ctx.policy_scope(User) }
    assert_raises(Mcp::ToolBug) { ctx.policy_scope(Gateway) } # inherited from AdminPolicy
    assert_includes ctx.policy_scope(BadgeAssignment, unfiltered: true), BadgeAssignment.find_by!(badge: @access_badge)
    assert_kind_of ActiveRecord::Relation, ctx.policy_scope(Person)
  end

  test "the unfiltered list matches the policies whose resolve is unconditional" do
    Rails.application.eager_load!
    unconditional = ApplicationPolicy.descendants.map { |policy| policy.const_get(:Scope) }.uniq.select do |scope|
      body = method_body(scope.instance_method(:resolve))
      body.size == 1 && body.first.match?(/\Ascope(\.all)?\z/)
    end

    assert_equal Mcp::Context::UNFILTERED_SCOPES.sort, unconditional.map(&:name).sort
  end

  test "the forwarding list matches the policy queries that only call a default query" do
    Rails.application.eager_load!
    forwarding = ApplicationPolicy.descendants.flat_map do |policy|
      policy.public_instance_methods(false).select { |query| query.end_with?("?") && allows_everyone?(policy, query) }
        .map { |query| "#{policy}##{query}" }
    end

    assert_equal Mcp::Context::FORWARDING_QUERIES.sort, forwarding.sort
  end

  test "method_body ignores comment lines" do
    assert_equal [ "scope.all" ], method_body(LedgerEntryLinkPolicy::Scope.instance_method(:resolve))
  end

  test "policy_scope refuses LedgerEntryLink, whose resolve has a comment above scope.all" do
    assert_raises(Mcp::ToolBug) { mcp_context(user(:alpha_member)).policy_scope(LedgerEntryLink) }
  end

  test "authorize! and allowed? refuse a query that forwards to a default" do
    ctx = mcp_context(user(:alpha_member))
    period = TimeClockPeriod.new(team: @beta)

    assert_raises(Mcp::ToolBug) { ctx.authorize!(period, :summary?) }
    assert_raises(Mcp::ToolBug) { ctx.allowed?(period, :summary?) }
    %i[badges? pages? events?].each do |query|
      assert_raises(Mcp::ToolBug) { ctx.authorize!(@beta, query) }
      assert_raises(Mcp::ToolBug) { ctx.allowed?(@beta, query) }
    end
    assert_raises(Mcp::ToolBug) { ctx.authorize!(Question.new, :upvote?) }
  end

  test "allowed? answers as a condition, using the policy's own rule" do
    assert_equal true, mcp_context(user(:admin)).allowed?(@alpha, :show_full?)
    assert_equal true, mcp_context(user(:alpha_member)).allowed?(@alpha, :show_full?)
    assert_equal false, mcp_context(user(:beta_member)).allowed?(@alpha, :show_full?)
    assert_equal true, mcp_context(user(:alpha_manager)).allowed?(@alpha, :manage_members?)
    assert_equal false, mcp_context(user(:alpha_member)).allowed?(@alpha, :manage_members?)
  end

  test "allowed? refuses a query only ApplicationPolicy implements" do
    assert_raises(Mcp::ToolBug) { mcp_context(user(:admin)).allowed?(@alpha, :show?) }
    assert_raises(Mcp::ToolBug) { mcp_context(user(:admin)).allowed?(BareRecord.new, :destroy?) }
  end

  test "policy_class names the policy a page uses, for both checks" do
    admin = mcp_context(user(:admin))
    member = mcp_context(user(:alpha_member))

    assert_raises(Mcp::ToolBug) { admin.authorize!(@access_badge, :index?) } # BadgePolicy has no index?
    assert_equal true, admin.allowed?(@access_badge, :index?, policy_class: BadgeAssignmentPolicy)
    assert_equal false, member.allowed?(@access_badge, :index?, policy_class: BadgeAssignmentPolicy)
    assert admin.authorize!(@access_badge, :index?, policy_class: BadgeAssignmentPolicy)
    assert_raises(Pundit::NotAuthorizedError) { member.authorize!(@access_badge, :index?, policy_class: BadgeAssignmentPolicy) }
  end

  test "the guard applies to the policy_class it's given" do
    ctx = mcp_context(user(:admin))

    assert_raises(Mcp::ToolBug) { ctx.authorize!(@access_badge, :show?, policy_class: BarePolicy) }
    assert_raises(Mcp::ToolBug) { ctx.allowed?(@access_badge, :show?, policy_class: BarePolicy) }
  end

  test "authorize! refuses a query only ApplicationPolicy implements" do
    ctx = mcp_context(user(:admin))

    assert_raises(Mcp::ToolBug) { ctx.authorize!(@alpha, :show?) }
    assert_raises(Mcp::ToolBug) { ctx.authorize!(@alpha, :index?) }
    assert_raises(Mcp::ToolBug) { ctx.authorize!(person(:admin).memberships.new, :show?) }
    assert ctx.authorize!(person(:admin), :show?)
  end

  test "authorize! allows delegating queries only when the policy defines the target" do
    admin = mcp_context(user(:admin))
    member = mcp_context(user(:alpha_member))

    assert admin.authorize!(@alpha, :edit?) # TeamPolicy#update?
    assert admin.authorize!(@alpha, :destroy?)
    assert_raises(Pundit::NotAuthorizedError) { member.authorize!(@beta, :edit?) }

    bare = BareRecord.new
    %i[show? index? create? update? new? edit? destroy?].each do |query|
      assert_raises(Mcp::ToolBug) { admin.authorize!(bare, query) }
    end
  end

  test "a tool bug is logged and raised, not returned as a tool result" do
    with_tool(read_tool("test_bug") { { rows: ctx.policy_scope(Checkin).count } }) do
      assert_raises(Mcp::ToolBug) { call_tool("test_bug", user: user(:admin)) }

      log = McpToolCall.order(:created_at).last
      assert_equal "test_bug", log.tool
      assert_equal "error", log.outcome
      assert_equal "Internal error", log.error_message
    end
  end

  # --- Running like the server

  test "call_tool runs in the app's time zone with the user as audit user" do
    tool = read_tool("test_request") { { zone: Time.zone.name, whodunnit: PaperTrail.request.whodunnit } }
    with_tool(tool) do
      with_settings(time_zone: "America/Detroit") do
        value = call_tool("test_request", user: user(:alpha_member)).value

        assert_equal "America/Detroit", value["zone"]
        assert_equal user(:alpha_member).id, value["whodunnit"]
      end
    end
  end

  test "call_tool gives a write tool its scope and the setting, so the policy decides" do
    target = person(:alpha_member)
    badge = @access_badge
    tool = Class.new(Mcp::Tool) do
      tool_name "test_write_policy"
      description "Test tool"
      scope :write
      define_method(:call) do
        assignment = BadgeAssignment.new(person: target, badge: badge)
        ctx.authorize!(assignment, :create?)
        assignment.save!
        changed!(assignment)
        { id: assignment.neat_id }
      end
    end
    with_tool(tool) do
      refused = call_tool("test_write_policy", user: user(:alpha_member))
      assert_equal "Not allowed", refused.error
      assert_equal 0, BadgeAssignment.where(person: target, badge: badge).count

      assert_not call_tool("test_write_policy", user: user(:admin)).error?
      assert_equal "BadgeAssignment", McpToolCall.order(:created_at).last.changed_type
    end
  end

  test "call_tool fails a successful write tool that didn't call changed!" do
    with_tool(tool_class("test_write_silent", scope: :write)) do
      error = assert_raises(Minitest::Assertion) { call_tool("test_write_silent", user: user(:admin)) }
      assert_match(/without calling changed!/, error.message)
    end
  end

  # --- Output helpers

  test "list refuses an unordered relation" do
    with_tool(read_tool("test_unordered") { list(ctx.policy_scope(Person), limit: 5) { |person| person_json(person) } }) do
      assert_raises(Mcp::ToolBug) { call_tool("test_unordered", user: user(:admin)) }
    end
  end

  test "format helpers follow the spec's formats, in the app's time zone" do
    tool = read_tool("test_formats") do
      moment = Time.utc(2026, 1, 2, 3, 4, 5)
      {
        time: time_json(moment), no_time: time_json(nil),
        date: date_json(moment), plain_date: date_json(Date.new(2026, 3, 4)), no_date: date_json(nil),
        hours: hours_json(1.23456), no_hours: hours_json(nil),
        money: money_json(Money.new(12_345)), cents: money_json(-50), no_money: money_json(nil)
      }
    end
    with_tool(tool) do
      with_settings(time_zone: "America/Detroit") do
        value = call_tool("test_formats", user: user(:admin)).value

        assert_equal "2026-01-01T22:04:05-05:00", value["time"]
        assert_equal "2026-01-01", value["date"]
        assert_equal "2026-03-04", value["plain_date"]
        assert_equal 1.23, value["hours"]
        assert_equal({ "cents" => 12_345, "formatted" => Money.new(12_345).format }, value["money"])
        assert_equal(-50, value["cents"]["cents"])
        assert_nil value["no_time"]
        assert_nil value["no_date"]
        assert_nil value["no_hours"]
        assert_nil value["no_money"]
      end
    end
  end

  # --- Call log contents

  test "a NUL in any argument is refused before the tool runs, and logged" do
    ran = false
    tool = read_tool("test_nul") { ran = true; { ok: true } }
    with_tool(tool) do
      [ { junk: "a\u0000b" }, { junk: { deep: [ "\u0000" ] } }, { "ke\u0000y": 1 } ].each do |arguments|
        assert_difference "McpToolCall.count", 1 do
          assert_equal "Arguments can't contain NUL characters", call_tool("test_nul", user: user(:admin), **arguments).error
        end
      end
    end
    assert_not ran
  end

  test "a NUL in a declared argument is replaced in the log" do
    assert_difference "McpToolCall.count", 1 do
      call_tool("search_people", user: user(:admin), query: "a\u0000b")
    end

    assert_equal "[not logged: contains a NUL character]", McpToolCall.order(:created_at).last.arguments["query"]
  end

  test "a row exists even when the arguments can't be stored" do
    result = Mcp::Tool::Result.new(outcome: :ok)

    assert_difference "McpToolCall.count", 1 do
      Mcp::CallLog.record(ctx: mcp_context(user(:admin)), tool: Mcp::Tools::SearchPeople, arguments: { "query" => "bad\xFF" }, result: result)
    end
    assert_equal Mcp::CallLog::NOT_STORABLE, McpToolCall.order(:created_at).last.arguments
  end

  test "only declared arguments are logged" do
    call_tool("search_people", user: user(:admin), query: "World", junk: "x" * 50)

    assert_equal({ "query" => "World" }, McpToolCall.order(:created_at).last.arguments)
  end

  test "a value over the cap is replaced by a placeholder giving its size" do
    limit = Mcp::CallLog::MAX_ARGUMENT_LENGTH
    call_tool("search_people", user: user(:admin), query: "x" * limit)
    assert_equal limit, McpToolCall.order(:created_at).last.arguments["query"].length

    call_tool("search_people", user: user(:admin), query: "x" * (limit + 1))
    assert_equal "[not logged: #{limit + 1} characters]", McpToolCall.order(:created_at).last.arguments["query"]
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
