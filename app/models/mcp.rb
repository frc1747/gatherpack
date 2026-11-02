# The MCP server's tool registry. Tools are Mcp::Tool subclasses, one per
# file in app/models/mcp/tools/, registered by name:
#
#   Mcp.register_tool(Mcp::Tools::SearchPeople)
#   Mcp.tools            # registered classes, in registration order
#   Mcp.tool("whoami")   # by name, or nil
#
# Registration happens in to_prepare blocks, which run again after every
# code reload in development. config/initializers/mcp.rb calls Mcp.reset!
# and then registers the core tools. Connector initializers are named
# config/initializers/mcp_<feature>.rb and register in their own to_prepare
# block: Rails loads initializers in sorted order and runs to_prepare blocks
# in the order they were added, so "mcp.rb" (and its reset) always comes
# before "mcp_<feature>.rb". A connector registers only when its feature
# exists in this build:
#
#   Rails.application.config.to_prepare do
#     next unless Mcp.feature_registered?(:forms)
#     Mcp.register_tool(Mcp::Tools::ListForms)
#   end
module Mcp
  # A tool failure that is returned to the client as a tool result
  # (isError: true) with this message. outcome is what the call log records.
  class Error < StandardError
    def outcome
      :error
    end
  end

  class NotFound < Error
    def initialize(message = "Not found")
      super
    end
  end

  class NotAllowed < Error
    def initialize(message = "Not allowed")
      super
    end

    def outcome
      :denied
    end
  end

  class InvalidArgument < Error; end

  class FeatureOff < NotAllowed
    def initialize(message = "Feature off")
      super
    end
  end

  class WritesDisabled < NotAllowed
    def initialize(message = "Writes disabled")
      super
    end
  end

  class DuplicateTool < StandardError; end

  # A mistake in a tool's code, such as relying on a default-true policy.
  # Mcp::Tool.run logs it and raises it again rather than turning it into a
  # tool result, so the tool fails in every test that reaches it.
  class ToolBug < ArgumentError; end

  SCOPES = %w[mcp_read mcp_write].freeze

  @tools = {}
  @person_extensions = []

  class << self
    def register_tool(klass)
      name = klass.tool_name.to_s
      raise ArgumentError, "#{klass} has no tool_name" if name.blank?
      raise ArgumentError, "MCP tool #{name} must declare a description" if klass.description.blank?
      raise ArgumentError, "MCP tool #{name} must declare a scope (:read or :write)" if klass.scope.nil?
      raise DuplicateTool, "MCP tool #{name} is already registered" if @tools.key?(name)

      @tools[name] = klass
    end

    # For tests that register a tool of their own.
    def unregister_tool(name)
      @tools.delete(name.to_s)
    end

    def reset!
      @tools = {}
      @person_extensions = []
    end

    # Callables (person, viewer) -> Hash whose keys get_person adds to its
    # result, viewer being the token's Person. A connector registers one in its
    # to_prepare block:
    #
    #   Mcp.person_extensions << ->(person, viewer) { { fields: ... } }
    #
    # It can't replace a key get_person returns itself. One that raises is
    # logged and left out of that call; the rest still apply.
    def person_extensions
      @person_extensions
    end

    def tools
      @tools.values
    end

    def tool(name)
      @tools[name.to_s]
    end

    # The tools a context may list and call: feature on, scope granted,
    # writes allowed for write tools.
    def available_tools(ctx)
      tools.select { |tool| tool.available?(ctx) }
    end

    # Whether the grants table has Doorkeeper's PKCE columns. Read at call time.
    def pkce_supported?
      Doorkeeper::AccessGrant.pkce_supported?
    end

    def feature_registered?(key)
      GatherPack::Features.all.any? { |feature| feature.key == key }
    end

    # Whether a JSON value holds a NUL character at any depth. Postgres can't
    # store one in jsonb or text.
    def contains_nul?(value)
      case value
      when String then value.include?("\0")
      when Hash then value.any? { |key, item| contains_nul?(key.to_s) || contains_nul?(item) }
      when Array then value.any? { |item| contains_nul?(item) }
      else false
      end
    end

    # Looks a record up by neat ID within scope (a relation or a model),
    # applying no policy: tools use Mcp::Context#find, which does. Returns nil
    # for a blank or malformed ID, an ID with another model's prefix, or a
    # record outside scope.
    def find_by_neat_id(scope, neat_id)
      klass = scope.is_a?(Class) ? scope : scope.klass
      return nil unless neat_id.is_a?(String) && klass.respond_to?(:_neat_id) && klass._neat_id

      prefix, = NeatIds.split_id(neat_id)
      return nil unless prefix == klass._neat_id.prefix

      id = klass.decode_neat_id(neat_id)
      id.is_a?(String) ? scope.find_by(id: id) : nil
    rescue ArgumentError
      nil
    end
  end
end
