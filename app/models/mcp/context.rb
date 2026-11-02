# What a tool runs as: the token's user and person, the token's scopes, the
# OAuth application and the request id. Tools do their own permission checks
# through it, as the token's user.
class Mcp::Context
  # Policy scopes whose resolve returns every row whoever is asking, including
  # those inherited by subclasses (GatewayPolicy::Scope is AdminPolicy::Scope).
  # A list of these isn't a permission check; see #policy_scope.
  UNFILTERED_SCOPES = %w[
    AdminPolicy::Scope
    ArchitectPolicy::Scope
    BadgeAssignmentPolicy::Scope
    CheckinPolicy::Scope
    LedgerEntryLinkPolicy::Scope
    LedgerPaymentPolicy::Scope
    LedgerTransferPolicy::Scope
    OauthApplicationPolicy::Scope
    UserPolicy::Scope
  ].freeze

  # ApplicationPolicy queries that only call another query.
  DELEGATING_QUERIES = { new?: :create?, edit?: :update?, destroy?: :update? }.freeze

  # Queries a policy defines whose whole body calls a query only
  # ApplicationPolicy implements, so they allow everyone too. Gate on a policy
  # scope instead: the summary page, for one, relies on
  # policy_scope(TimeClockPeriod), not on summary?.
  FORWARDING_QUERIES = %w[
    QuestionPolicy#upvote?
    TeamPolicy#badges?
    TeamPolicy#events?
    TeamPolicy#pages?
    TimeClockPeriodPolicy#summary?
  ].freeze

  attr_reader :user, :person, :scopes, :application, :request_id

  def initialize(user:, scopes:, application: nil, request_id: nil)
    @user = user
    @person = user.person
    @scopes = Array(scopes).map(&:to_s)
    @application = application
    @request_id = request_id
  end

  # :read is granted by mcp_read or mcp_write; :write only by mcp_write.
  def scope?(level)
    case level&.to_sym
    when :read then scopes.intersect?(Mcp::SCOPES)
    when :write then scopes.include?("mcp_write")
    else false
    end
  end

  def writes_allowed?
    scope?(:write) && Mcp::Access.writes_enabled?
  end

  # The app's time zone and audit log user, as ApplicationController sets them
  # for a page. Mcp::Tool.run calls tools inside this.
  def in_request(&block)
    PaperTrail.request(whodunnit: user.id) do
      Time.use_zone(Settings[:time_zone].presence || "UTC", &block)
    end
  end

  # Pundit's scope as the token's user. Raises Mcp::ToolBug for a scope in
  # UNFILTERED_SCOPES: gate on the parent record the page is reached through
  # instead. Where the whole table really is right, pass unfiltered: true and
  # give the reason in the tool's class comment.
  def policy_scope(scope, unfiltered: false)
    scope_class = Pundit::PolicyFinder.new(scope).scope!
    if !unfiltered && UNFILTERED_SCOPES.include?(scope_class.name)
      raise Mcp::ToolBug, "#{scope_class} returns every row; gate on a parent record or pass unfiltered: true"
    end

    Pundit.policy_scope!(user, scope)
  end

  # Raises Pundit::NotAuthorizedError, which a tool call returns as
  # "Not allowed". Raises Mcp::ToolBug for a query that allows everyone: one
  # only ApplicationPolicy implements, or one in FORWARDING_QUERIES. policy_class
  # names the policy where the page uses one other than the record's own.
  def authorize!(record, query, policy_class: nil)
    guarded_policy(record, query, policy_class)
    Pundit.authorize(user, record, query.to_sym, policy_class: policy_class)
  end

  # The same check as a condition, for rules like "all holders if allowed,
  # otherwise only those in scope". Same guard and same policy_class as
  # #authorize!; use this rather than calling a policy directly.
  def allowed?(record, query, policy_class: nil)
    guarded_policy(record, query, policy_class).public_send(query.to_sym) ? true : false
  end

  # The record with this neat ID in scope, or Mcp::NotFound: a wrong prefix
  # and a record the user can't see look the same. A model is narrowed with
  # policy_scope first; a relation is used as given, for a policy scope that
  # has already been narrowed.
  def find(scope, neat_id)
    scope = policy_scope(scope) if scope.is_a?(Class)
    Mcp.find_by_neat_id(scope, neat_id) || raise(Mcp::NotFound)
  end

  private

  def guarded_policy(record, query, policy_class)
    query = query.to_sym
    policy = policy_class ? policy_class.new(user, record) : Pundit.policy!(user, record)
    unless policy_defines?(policy, query)
      raise Mcp::ToolBug, "#{policy.class} doesn't define #{query}, so ApplicationPolicy allows everyone"
    end

    owner = policy.method(query).owner
    if FORWARDING_QUERIES.include?("#{owner}##{query}")
      raise Mcp::ToolBug, "#{owner}##{query} only calls a default query, so it allows everyone"
    end

    policy
  end

  def policy_defines?(policy, query)
    return true unless policy.method(query).owner == ApplicationPolicy

    delegate = DELEGATING_QUERIES[query]
    delegate.present? && policy_defines?(policy, delegate)
  end
end
