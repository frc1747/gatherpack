# Where a request's money comes from: a budget or a restricted gift, kept in
# GatherPack or not. It's a label with an optional limit, not bookkeeping:
# spent and committed come from orders' own purchases and lines.
class FundingSource < ApplicationRecord
  has_neat_id :fund
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :team
  belongs_to :budget, optional: true
  has_many :order_requests, dependent: :restrict_with_error
  has_many :direct_order_lines, class_name: "OrderLine", dependent: :restrict_with_error
  has_many_attached :documents

  enum :kind, { general: 0, restricted: 1 }

  monetize :amount_cents, allow_nil: true
  monetize :spent_outside_cents

  validates :name, presence: true
  validates :restriction, presence: true, if: :restricted?
  validate :dates_in_order

  scope :active, -> { where(active: true) }

  # The fields only funding managers, approvers and admins see.
  RESTRICTED_FIELDS = %w[giver reference documents report_due_on].freeze

  def self.ransackable_attributes(auth_object = nil)
    %w[name kind active team_id]
  end

  def identifier_icon
    "hand-holding-dollar"
  end

  # Usable by requests from its team and the teams below.
  def usable_by?(team)
    team.present? && usable_team_ids.include?(team.id)
  end

  def usable_team_ids
    [ team_id ] + team.all_descendant_ids
  end

  def spendable_on?(date)
    return true if date.nil?

    (starts_on.nil? || date >= starts_on) && (ends_on.nil? || date <= ends_on)
  end

  # Lines charged to this source: their own source, or their request's
  # when they name none.
  def order_lines
    OrderLine.joins(:order_request)
      .where("COALESCE(order_lines.funding_source_id, order_requests.funding_source_id) = ?", id)
  end

  def numbers
    @numbers ||= Orders::FundingNumbers.new(self)
  end

  delegate :spent_cents, :committed_cents, :remaining_cents, to: :numbers

  def spent
    Money.new(spent_cents)
  end

  def committed
    Money.new(committed_cents)
  end

  def remaining
    remaining_cents && Money.new(remaining_cents)
  end

  # Links the source to a GatherPack Budget, or unlinks it with nil (spec
  # §6). Requests still pick the source, never the Budget.
  def link_budget!(budget)
    raise Orders::Refused, "Budgets are turned off." unless Orders::LedgerRecording.budgets_on?

    update!(budget: budget)
  end

  def reload(*)
    @numbers = nil
    super
  end

  private

  def dates_in_order
    return if starts_on.nil? || ends_on.nil? || ends_on >= starts_on

    errors.add(:ends_on, "must be on or after the start")
  end
end
