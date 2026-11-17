# One person's ask for things to be bought, for a team. Approval is per
# request (Orders::ApprovalEngine); buying and receiving are per line, and
# once a request is approved its ordering and received states follow its
# lines (#refresh_status_from_lines).
#
# Every change goes through a method in Orders::RequestActions, the approval
# engine or OrderLine, which takes the request's row lock and writes its
# timeline entry (OrderRequestEvent) in the same transaction.
class OrderRequest < ApplicationRecord
  has_neat_id :ordr
  include CanBeHooked
  include Orders::ApprovalEngine
  include Orders::RequestActions
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :team
  belongs_to :requested_by, class_name: "Person"
  belongs_to :funding_source, optional: true
  has_many :order_lines, -> { order(:position, :created_at) }, inverse_of: :order_request, dependent: :destroy
  has_many :order_approvals, -> { order(:created_at) }, inverse_of: :order_request, dependent: :destroy
  has_many :order_request_watchers, dependent: :destroy
  has_many :watchers, through: :order_request_watchers, source: :person
  # The timeline can't be deleted, so neither can a request that has one
  # (anything past a draft).
  has_many :events, -> { order(:created_at) }, class_name: "OrderRequestEvent", inverse_of: :order_request, dependent: :restrict_with_error

  enum :status, {
    draft: 0, submitted: 1, changes_requested: 2, approved: 3, ordering: 4,
    received: 5, closed: 6, declined: 7, cancelled: 8
  }

  monetize :estimated_shipping_cents
  monetize :approved_total_cents, allow_nil: true

  validates :estimated_shipping_cents, numericality: { greater_than_or_equal_to: 0 }
  validate :funding_source_usable
  validate :team_is_requesters

  # Statuses a requester may still edit in, and those that are over.
  EDITABLE_STATUSES = %w[draft submitted changes_requested].freeze
  FINISHED_STATUSES = %w[received closed declined cancelled].freeze
  # Active for Your orders: what someone is still waiting on.
  ACTIVE_STATUSES = %w[draft submitted changes_requested approved ordering].freeze

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :open, -> { where.not(status: %w[draft] + FINISHED_STATUSES) }

  after_save :remember_status_change
  after_commit :announce_status_changes

  def self.ransackable_attributes(auth_object = nil)
    %w[title status team_id requested_by_id needed_by submitted_at created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[team requested_by]
  end

  # The supported way for another feature to start a request (inventory's
  # reorder): a draft the person then submits, so nothing skips approval.
  # Each of lines is a hash of OrderLine attributes.
  def self.draft_for(person:, team:, lines:, **attributes)
    transaction do
      order_request = create!(attributes.merge(requested_by: person, team: team, status: :draft))
      Array(lines).each_with_index do |line, index|
        order_request.order_lines.create!(line.to_h.symbolize_keys.merge(position: index))
      end
      order_request
    end
  end

  def identifier_name
    display_title
  end

  def identifier_icon
    "cart-shopping"
  end

  def display_title
    title.presence || order_lines.first&.display_name || "Order request"
  end

  def editable?
    status.in?(EDITABLE_STATUSES)
  end

  def finished?
    status.in?(FINISHED_STATUSES)
  end

  # Sum of the live lines' quantity × price (actual where known, else
  # estimated) plus the estimated shipping. Uses loaded lines, so a list
  # that preloads them asks no more queries.
  def total_cents
    live_lines.sum(&:cost_cents) + estimated_shipping_cents.to_i
  end

  def total
    Money.new(total_cents)
  end

  def live_lines
    order_lines.reject(&:cancelled?)
  end

  def watched_by?(person)
    person.present? && order_request_watchers.any? { |watcher| watcher.person_id == person.id }
  end

  # The lines waiting for a buyer's change to be approved again.
  def reapproval_lines
    order_lines.select(&:needs_reapproval?)
  end

  def needs_reapproval?
    (approved? || ordering?) && reapproval_lines.any?
  end

  # "2 of 3 received", for the list wording once lines are on purchases.
  def received_count_text
    lines = live_lines
    "#{lines.count(&:received?)} of #{lines.size} received"
  end

  # The funding sources this request uses: its own and any its lines name.
  def funding_sources_used
    ids = ([ funding_source_id ] + live_lines.map(&:funding_source_id)).compact.uniq
    ids.empty? ? [] : FundingSource.where(id: ids).to_a
  end

  # Writes a timeline entry. Called inside the action's transaction.
  def log!(action, by:, line: nil, step_key: nil, changes: {}, comment: nil)
    events.create!(action: action.to_s, actor: by, order_line: line, step_key: step_key,
      field_changes: changes, comment: comment.presence)
  end

  # Runs the block in a transaction holding this request's row lock, so two
  # people can't change it (or put its lines on two purchases) at once.
  def locked
    transaction do
      lock!
      yield
    end
  end

  private

  def funding_source_usable
    return if funding_source.nil? || !(will_save_change_to_funding_source_id? || will_save_change_to_team_id?)

    errors.add(:funding_source, "can't be used by #{team&.name}") unless funding_source.usable_by?(team)
  end

  # A request is for one of its requester's teams (or one they manage), so
  # it can't be steered to another team's approvers.
  def team_is_requesters
    return if team.nil? || requested_by.nil? || !will_save_change_to_team_id?
    return if Orders::Access.new(requested_by).may_request_for?(team_id)

    errors.add(:team, "must be one of #{requested_by.identifier_name}'s teams")
  end

  def remember_status_change
    return unless saved_change_to_status?

    (@status_changes ||= []) << saved_change_to_status
  end

  def announce_status_changes
    changes = @status_changes
    @status_changes = nil
    Array(changes).each do |from, to|
      Orders.request_changed(self, from, to)
      event = Orders::STATUS_CHANGED_EVENTS[to]
      next if event.nil?
      # Approved only counts from a decision, not a recount of lines.
      next if to == "approved" && from != "submitted"

      Orders.run_hooks(event, self)
    end
  end
end
