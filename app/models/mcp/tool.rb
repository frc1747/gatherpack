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
# A write tool calls changed!(record) so the call log records what changed;
# changed!(record, *others) when one action also created or changed others.
# ctx.policy_scope, ctx.authorize!, ctx.allowed? and list raise Mcp::ToolBug for
# a check that wouldn't protect anything; that isn't a tool result, it fails the
# test. For a condition use ctx.allowed?, not the policy directly.
#
# Tools run in the app's time zone with the token's user as the audit log user.
# Format values with time_json, date_json, hours_json and money_json.
#
# A bulk tool (only where a page has the same bulk action) declares `bulk`, takes
# dry_run: dry_run_property, and does its work through bulk_write, which returns
# { changed:, skipped: [{ id:, reason: }], dry_run: } for output_schema(bulk_output_schema(item)).
#
# mask_argument(:value, with: ->(value) { ... }) stores an argument masked in the
# call log. Masking doesn't reach the Rails log: that's filter_parameters.
#
# Tools don't use the MCP SDK directly: Mcp::Server adapts them with to_sdk.
class Mcp::Tool
  DEFAULT_LIMIT = 25
  MAX_LIMIT = 100
  BULK_LIMIT = 200
  MASKED = "[masked]".freeze

  # Output schema of person_json and team_json.
  REF_SCHEMA = {
    type: "object",
    properties: { id: { type: "string" }, name: { type: "string" } },
    required: %w[id name]
  }.freeze

  # The outcome of one call. value is the JSON-ready result (string keys),
  # error the message returned when the call failed, changed the record a
  # write tool changed, changed_records every record the call changed (a bulk
  # tool's changed stays nil: there's no one record).
  Result = Data.define(:value, :error, :outcome, :changed, :changed_records) do
    def initialize(outcome:, value: nil, error: nil, changed: nil, changed_records: [])
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

    # closed: true refuses arguments not listed, by name. For a write tool whose
    # page takes more than the tool does, so a client's phone number isn't dropped
    # with a success. Otherwise undeclared arguments are ignored.
    def input_schema(properties: nil, required: [], closed: false)
      return @input_schema || { type: "object", properties: {} } if properties.nil?

      @input_schema = { type: "object", properties: properties, required: required.map(&:to_s) }
      @input_schema[:additionalProperties] = false if closed
      @input_schema
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

    # Marks a write tool as changing several records in one call. See bulk_write.
    def bulk
      @bulk = true
    end

    def bulk?
      write? && @bulk == true
    end

    # Input schema property every bulk tool takes.
    def dry_run_property
      { type: "boolean", description: "List what would change without changing it (default false)" }
    end

    # Output schema of bulk_write, item_schema describing one changed record.
    def bulk_output_schema(item_schema)
      {
        type: "object",
        properties: {
          changed: { type: "array", items: item_schema },
          skipped: {
            type: "array",
            items: { type: "object", properties: { id: { type: "string" }, reason: { type: "string" } }, required: %w[id reason] }
          },
          dry_run: { type: "boolean" }
        },
        required: %w[changed skipped dry_run]
      }
    end

    # Stores these arguments in the call log as with.call(value). The default keeps nothing.
    def mask_argument(*names, with: ->(_value) { MASKED })
      names.each { |name| masked_arguments[name.to_s] = with }
    end

    def masked_arguments
      @masked_arguments ||= {}
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
      result = result.with(changed: tool.changed_record, changed_records: tool.changed_records)

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

  attr_reader :ctx, :changed_record, :changed_records

  def initialize(ctx)
    @ctx = ctx
    @changed_records = []
  end

  def call(**)
    raise NotImplementedError, "#{self.class} must implement #call"
  end

  private

  # record goes in the call log's changed_type and changed_id; it and others in its
  # changed_records.
  def changed!(record, *others)
    @changed_record = record
    @changed_records = [ record, *others ]
  end

  # Does one bulk action, for a tool that declared `bulk`:
  #
  #   bulk_write(punches, dry_run: dry_run,
  #     check: ->(punch) { raise Mcp::NotAllowed unless may_close?(punch) },
  #     json: ->(punch) { punch_json(punch) }) { |punch| punch.update(end_time: end_of(punch)) }
  #
  # check runs for every record, with the same rule as the single-record tool. If it
  # raises a refusal, the record is skipped with that message as its reason. More than
  # BULK_LIMIT records passing it refuses the whole call before anything changes.
  #
  # With dry_run, nothing else runs: changed lists the records that passed check, and
  # the call log's changed_records stays empty. So check has to include whatever could
  # still refuse a record for dry_run to promise the same list as a real run.
  #
  # Otherwise the block writes each record in its own save (never update_all, so hooks
  # fire). A record whose block returns false, or raises a refusal or a validation
  # error, is skipped, and the others still go ahead. Each change reaches the call log
  # as it's made, so the log is right even if a later record fails with an exception.
  def bulk_write(records, json:, dry_run: false, check: nil, &write)
    raise Mcp::ToolBug, "#{self.class} must declare bulk to use bulk_write" unless self.class.bulk?

    skipped = []
    writable = records.select { |record| bulk_outcome(record, skipped) { check&.call(record) } }
    if writable.size > BULK_LIMIT
      raise Mcp::InvalidArgument, "This would change #{writable.size} records, and a call can change at most #{BULK_LIMIT}"
    end

    changed = writable.select do |record|
      next true if dry_run

      bulk_outcome(record, skipped) do
        raise Mcp::InvalidArgument, record.errors.full_messages.to_sentence if write.call(record) == false
      end.tap { |written| @changed_records << record if written }
    end
    { changed: changed.map(&json), skipped: skipped, dry_run: dry_run }
  end

  # Whether the block finished; if it refused, adds the record and why to skipped.
  def bulk_outcome(record, skipped)
    yield
    true
  rescue Mcp::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved, ActiveRecord::RecordNotDestroyed => e
    skipped << { id: record.neat_id, reason: e.message }
    false
  rescue Pundit::NotAuthorizedError
    skipped << { id: record.neat_id, reason: Mcp::NotAllowed.new.message }
    false
  end

  def not_found!
    raise Mcp::NotFound
  end

  def invalid_argument!(message)
    raise Mcp::InvalidArgument, message
  end

  # The name falls back to first and last name, then the ID, for a person
  # without a display name, so the name is always a string.
  def person_json(person)
    { id: person.neat_id, name: person.display_name.presence || [ person.first_name, person.last_name ].compact_blank.join(" ").presence || person.neat_id }
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
