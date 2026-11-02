# Base class for MCP tools. Each tool is one subclass in app/models/mcp/tools/
# that declares itself with the class methods below and implements #call
# with keyword arguments matching its input schema:
#
#   class Mcp::Tools::SearchPeople < Mcp::Tool
#     tool_name "search_people"
#     description "Find people by name."  # required
#     scope :read                 # or :write; required
#     feature :badges             # GatherPack feature key(s) that must be on; omit for core
#     input_schema(properties: { query: { type: "string" } }, required: [ "query" ])
#     output_schema(...)          # optional, describes what #call returns
#
#     def call(query:)
#       people = ctx.policy_scope(Person) ...
#       list(people.order(:last_name, :id), limit: 25) { |person| person_json(person) }
#     end
#   end
#
# #call returns a Hash; it is sent as JSON (structuredContent plus the same
# JSON as a text block). Raise Mcp::NotFound, Mcp::NotAllowed or
# Mcp::InvalidArgument (or call not_found!, invalid_argument!) to return a
# tool error; a Pundit::NotAuthorizedError becomes "Not allowed". Any other
# exception is logged with the request id and returned as "Internal error".
# A write tool calls changed!(record) so the call log records what changed.
# ctx.policy_scope, ctx.authorize! and list raise Mcp::ToolBug for a check that
# wouldn't protect anything; that isn't a tool result, it fails the test.
#
# Tools run in the app's time zone with the token's user as the audit log user.
# Format values with time_json, date_json, hours_json and money_json.
#
# Tools don't use the MCP SDK directly: Mcp::Server adapts them with to_sdk.
class Mcp::Tool
  DEFAULT_LIMIT = 25
  MAX_LIMIT = 100

  # Output schema of person_json and team_json.
  REF_SCHEMA = {
    type: "object",
    properties: { id: { type: "string" }, name: { type: "string" } },
    required: %w[id name]
  }.freeze

  # The outcome of one call. value is the JSON-ready result (string keys),
  # error the message returned when the call failed, changed the record a
  # write tool changed.
  Result = Data.define(:value, :error, :outcome, :changed) do
    def initialize(outcome:, value: nil, error: nil, changed: nil)
      super
    end

    def error?
      !error.nil?
    end

    def to_response
      if error?
        MCP::Tool::Response.new([ { type: "text", text: error } ], error: true)
      else
        MCP::Tool::Response.new([ { type: "text", text: JSON.generate(value) } ], structured_content: value)
      end
    end
  end

  class << self
    def tool_name(value = nil)
      value.nil? ? @tool_name : (@tool_name = value.to_s)
    end

    def description(value = nil)
      value.nil? ? @description : (@description = value)
    end

    def scope(value = nil)
      return @scope if value.nil?
      raise ArgumentError, "scope must be :read or :write" unless %i[read write].include?(value)

      @scope = value
    end

    def write?
      scope == :write
    end

    def feature(*keys)
      @features = keys.flatten
    end

    def features
      @features || []
    end

    def input_schema(properties: nil, required: [])
      return @input_schema || { type: "object", properties: {} } if properties.nil?

      @input_schema = { type: "object", properties: properties, required: required.map(&:to_s) }
    end

    def output_schema(schema = nil)
      schema.nil? ? @output_schema : (@output_schema = schema)
    end

    # Extra MCP annotations, e.g. destructive: true on a removal.
    def destructive(value = true)
      @destructive = value
    end

    def destructive?
      write? && @destructive == true
    end

    def annotations
      { read_only_hint: scope == :read, destructive_hint: destructive?, idempotent_hint: scope == :read, open_world_hint: false }
    end

    # Input schema property for a list limit.
    def limit_property
      { type: "integer", minimum: 1, maximum: MAX_LIMIT, description: "At most this many results (default #{DEFAULT_LIMIT})" }
    end

    def argument_names
      input_schema[:properties].keys.map(&:to_s)
    end

    # Names of required arguments absent from arguments (string keys).
    def missing_arguments(arguments)
      sdk_input_schema.missing_required_arguments(arguments)
    end

    def available?(ctx)
      problem(ctx).nil?
    end

    # Runs the tool for ctx with arguments as the client sent them, logs the
    # call, and returns a Result. An Mcp::ToolBug is logged and raised again.
    def run(ctx, arguments)
      arguments = (arguments || {}).to_h.deep_stringify_keys
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      tool = new(ctx)
      bug = nil
      result = ctx.in_request do
        raise problem(ctx) if problem(ctx)

        validate_arguments!(arguments)
        value = tool.call(**arguments.slice(*argument_names).symbolize_keys)
        Result.new(value: value.as_json, outcome: :ok)
      rescue Mcp::Error => e
        Result.new(error: e.message, outcome: e.outcome)
      rescue Pundit::NotAuthorizedError
        Result.new(error: "Not allowed", outcome: :denied)
      rescue => e
        Rails.logger.error("[MCP] #{tool_name} failed (request #{ctx.request_id}): #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}")
        bug = e if e.is_a?(Mcp::ToolBug)
        Result.new(error: "Internal error", outcome: :error)
      end
      result = result.with(changed: tool.changed_record)

      Mcp::CallLog.record(ctx: ctx, tool: self, arguments: arguments, result: result,
        duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
      raise bug if bug

      result
    end

    # An MCP SDK tool class that runs this tool for ctx.
    def to_sdk(ctx)
      tool = self
      Class.new(MCP::Tool) do
        tool_name tool.tool_name
        description tool.description
        input_schema tool.input_schema
        output_schema tool.output_schema if tool.output_schema
        annotations(**tool.annotations)
        define_singleton_method(:call) { |server_context: nil, **arguments| tool.run(ctx, arguments).to_response }
      end
    end

    private

    # Why ctx can't call this tool, as an Mcp::Error, or nil.
    def problem(ctx)
      if !ctx.scope?(scope)
        Mcp::NotAllowed.new
      elsif features.any? { |key| !GatherPack::Features.enabled?(key) }
        Mcp::FeatureOff.new
      elsif write? && !Mcp::Access.writes_enabled?
        Mcp::WritesDisabled.new
      end
    end

    def validate_arguments!(arguments)
      raise Mcp::InvalidArgument, "Arguments can't contain NUL characters" if Mcp.contains_nul?(arguments)

      missing = missing_arguments(arguments)
      raise Mcp::InvalidArgument, "Missing required arguments: #{missing.join(", ")}" if missing.any?

      sdk_input_schema.validate_arguments(arguments)
    rescue MCP::Tool::InputSchema::ValidationError => e
      raise Mcp::InvalidArgument, e.message
    end

    def sdk_input_schema
      @sdk_input_schema ||= MCP::Tool::InputSchema.new(input_schema)
    end
  end

  attr_reader :ctx, :changed_record

  def initialize(ctx)
    @ctx = ctx
  end

  def call(**)
    raise NotImplementedError, "#{self.class} must implement #call"
  end

  private

  def changed!(record)
    @changed_record = record
  end

  def not_found!
    raise Mcp::NotFound
  end

  def invalid_argument!(message)
    raise Mcp::InvalidArgument, message
  end

  def person_json(person)
    { id: person.neat_id, name: person.display_name }
  end

  def team_json(team)
    { id: team.neat_id, name: team.name }
  end

  # ISO 8601 in the app's time zone.
  def time_json(time)
    time&.in_time_zone&.iso8601
  end

  # YYYY-MM-DD; a time is taken in the app's time zone.
  def date_json(date)
    date&.in_time_zone&.to_date&.iso8601
  end

  # Decimal hours, rounded to 0.01.
  def hours_json(hours)
    hours&.to_f&.round(2)
  end

  # A Money or integer cents as { cents:, formatted: }.
  def money_json(amount)
    return nil if amount.nil?

    money = amount.is_a?(Money) ? amount : Money.new(amount)
    { cents: money.cents, formatted: money.format }
  end

  # The first limit records of relation as { items:, truncated: }, each item
  # built by the block. The relation must be ordered, so pages are stable.
  def list(relation, limit:, &block)
    raise Mcp::ToolBug, "#{self.class} must order the relation it lists" if relation.order_values.empty?

    limit = limit.to_i.clamp(1, MAX_LIMIT)
    records = relation.limit(limit + 1).to_a
    { items: records.first(limit).map(&block), truncated: records.size > limit }
  end
end
