# A saved question about each person's money records ("2027 Membership
# Dues", "Total given this year"), answered from one accounting source's
# neutral columns. The kind decides how a person's matching records become
# a value and an amount (Accounting::Kinds); filters decide which records
# match; milestones say what has to be paid by when. Each person the rule
# applies to gets one AccountingRuleResult, saved by Accounting::Evaluation.
#
# read_permission says who sees a person's result and amount_permission who
# also sees the amounts and pay links, relative to that person
# (AudienceLevels); badge grants add treasurers and mentors who aren't
# leaders. Admins see everything.
class AccountingRule < ApplicationRecord
  has_neat_id :arl
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  KINDS = %w[ balance amount count custom ].freeze
  KIND_NAMES = { "balance" => "Balance remaining", "amount" => "Amount", "count" => "Count", "custom" => "Custom" }.freeze

  # The values each kind gives, in the order they're checked and listed.
  # These words are tied to code; their labels are renamable per rule.
  VALUES = {
    "balance" => %w[ not_invoiced paid overdue partial unpaid ],
    "amount" => %w[ some none ],
    "count" => %w[ some none ],
    "custom" => []
  }.freeze
  DEFAULT_LABELS = {
    "not_invoiced" => "Not invoiced", "paid" => "Paid", "overdue" => "Overdue", "partial" => "Partly paid",
    "unpaid" => "Not yet paid", "some" => "Some", "none" => "None", "error" => "Error"
  }.freeze
  # A custom rule's code raised. Shown to admins only.
  ERROR = "error".freeze

  UNAPPLIED_CREDIT = %w[ show count ].freeze
  MEASURES = %w[ invoiced paid ].freeze
  FILTER_KEYS = %w[ roles items classes locations txn_date_from txn_date_to due_date_from due_date_to min_total ].freeze
  KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/

  belongs_to :gateway
  belongs_to :team, optional: true
  has_many :milestones, -> { order(:due_on, :position) }, class_name: "AccountingRuleMilestone", foreign_key: :rule_id,
    inverse_of: :rule, dependent: :destroy
  has_many :badge_grants, class_name: "AccountingRuleBadgeGrant", foreign_key: :rule_id, inverse_of: :rule, dependent: :destroy
  has_many :results, class_name: "AccountingRuleResult", foreign_key: :rule_id, inverse_of: :rule, dependent: :delete_all

  accepts_nested_attributes_for :milestones, allow_destroy: true,
    reject_if: ->(attributes) { attributes.values_at("name", "due_on", "balance_at_most", "balance_at_most_percent").all?(&:blank?) }
  accepts_nested_attributes_for :badge_grants, allow_destroy: true, reject_if: ->(attributes) { attributes["badge_id"].blank? }

  enum :read_permission, AudienceLevels::LEVEL_VALUES, prefix: :read, validate: true
  enum :amount_permission, AudienceLevels::LEVEL_VALUES, prefix: :amounts, validate: true

  store_accessor :settings, :labels, :grace_days, :unapplied_credit, :measure, :show_pay_links

  before_validation :generate_key, on: :create
  before_validation :normalize_settings
  before_validation :normalize_filters

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :key, presence: true, uniqueness: true, format: { with: KEY_FORMAT, message: "must start with a letter and use only lowercase letters, numbers, and underscores" }
  validates :grace_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :unapplied_credit, inclusion: { in: UNAPPLIED_CREDIT }
  validates :measure, inclusion: { in: MEASURES }, if: -> { kind == "amount" }
  validates :code, presence: true, if: -> { kind == "custom" }
  validate :key_unchanged, on: :update
  validate :source_is_accounting
  validate :amounts_within_read
  validate :filter_dates_valid

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:position, :name) }

  def self.ransackable_attributes(auth_object = nil)
    %w[ name key kind enabled ]
  end

  def identifier_icon
    "file-invoice-dollar"
  end

  def identifier_name
    name
  end

  def kind_name
    KIND_NAMES.fetch(kind.to_s, kind.to_s.humanize)
  end

  def balance?
    kind == "balance"
  end

  def custom?
    kind == "custom"
  end

  # The values this rule gives, in order; a custom rule's are whatever its
  # code returned.
  def values
    VALUES.fetch(kind.to_s, [])
  end

  def label_for(value)
    return "" if value.nil?

    (labels.presence || {}).fetch(value.to_s, nil).presence || DEFAULT_LABELS.fetch(value.to_s) { value.to_s.humanize }
  end

  def grace_period
    grace_days.to_i.days
  end

  def show_pay_links?
    ActiveModel::Type::Boolean.new.cast(show_pay_links) == true
  end

  def count_unapplied_credit?
    unapplied_credit == "count"
  end

  def capabilities
    gateway.respond_to?(:capabilities) ? gateway.capabilities : Set.new
  end

  def pay_links?
    show_pay_links? && capabilities.include?(:pay_links)
  end

  # The milestones that apply to a person: the rule's own. A per-person
  # payment plan overrides this to return the plan's.
  def milestones_for(person)
    milestones.reject { |milestone| milestone.marked_for_destruction? || milestone.due_on.nil? }
  end

  # Whether the person follows their own milestones rather than the rule's.
  # Payment plans override this with #milestones_for.
  def on_plan?(person)
    false
  end

  # Whether the rule can never be Overdue: no milestones and a source whose
  # charges carry no due dates.
  def never_overdue?
    balance? && milestones_for(nil).empty? && !capabilities.include?(:due_dates)
  end

  # The roles this rule reads that its source doesn't copy. A rule that
  # needs one isn't evaluated.
  def missing_roles
    return [] unless gateway.respond_to?(:entity_types)

    copied = gateway.entity_types.values.map(&:to_s)
    needed_roles.reject { |role| copied.include?(role) }
  end

  def evaluable?
    missing_roles.empty?
  end

  # The roles the source must copy for the rule to be worked out: the ones
  # its filter names that the kind reads, else the ones the kind can't do
  # without (a paid amount matched by items, categories or locations reads
  # charges too).
  def needed_roles
    return filter_roles & read_roles if filter_roles.any?

    case kind
    when "balance" then [ "charge" ]
    when "amount" then measure == "paid" ? [ "payment", *("charge" if Accounting::RecordFilter.new(filters).lines?) ] : [ "charge" ]
    else []
    end
  end

  # Every role the kind reads.
  def read_roles
    case kind
    when "balance" then %w[ charge ]
    when "amount" then measure == "paid" ? %w[ payment receipt refund charge ] : %w[ charge receipt ]
    else Accounting::Kinds::Count::ROLES
    end
  end

  def filter_roles
    Array(filters&.fetch("roles", nil))
  end

  # Everyone the rule gives a result: the people linked to any customer of
  # its source, and the members of its team and the teams below it.
  def people
    linked = Person.where(id: AccountingCustomerLink.where(gateway_id: gateway_id).select(:person_id))
    team ? linked.or(Person.where(id: team.descendant_people.select(:id))) : linked
  end

  # The people whose results the viewer (a Person) may see. Must agree with
  # Accounting::RuleAccess#can_read?.
  def readable_people_for(viewer)
    return Person.none if viewer.nil?
    return people if viewer.admin?

    AudienceLevels.combine([ AudienceLevels.people(read_permission, viewer) ] + granted_people(viewer)).where(id: people.select(:id))
  end

  # The people whose amounts the viewer may see. Must agree with
  # Accounting::RuleAccess#can_see_amounts?.
  def amount_people_for(viewer)
    return Person.none if viewer.nil?
    return people if viewer.admin?

    level = AudienceLevels.people(amount_permission, viewer).where(id: AudienceLevels.people(read_permission, viewer).select(:id))
    AudienceLevels.combine([ level ] + granted_people(viewer, amounts: true)).where(id: people.select(:id))
  end

  # A copy for the next season: years in the name and every date moved on a
  # year, filters, milestones, visibility and grants kept, disabled. Never
  # results.
  def duplicate!
    transaction do
      copy = dup
      copy.assign_attributes(name: self.class.next_season_name(name), key: nil, enabled: false,
        filters: self.class.shift_filter_dates(filters), settings: settings.deep_dup)
      copy.save!
      milestones.each do |milestone|
        copy.milestones.create!(milestone.attributes.slice("name", "balance_at_most_cents", "balance_at_most_percent", "position")
          .merge("due_on" => milestone.due_on.next_year))
      end
      badge_grants.each { |grant| copy.badge_grants.create!(badge_id: grant.badge_id, amounts: grant.amounts, bill: grant.bill) }
      copy
    end
  end

  # "2026-27 Dues" becomes "2027-28 Dues", "Fees 2026" becomes "Fees 2027";
  # a name without a year gets " (copy)".
  def self.next_season_name(name)
    moved = name.gsub(/\b(\d{4})(?:([-–\/])(\d{2}|\d{4}))?\b/) do
      first = Regexp.last_match(1).to_i + 1
      second = Regexp.last_match(3)
      second ? "#{first}#{Regexp.last_match(2)}#{second.length == 2 ? format("%02d", (second.to_i + 1) % 100) : second.to_i + 1}" : first.to_s
    end
    moved == name ? "#{name} (copy)" : moved
  end

  def self.shift_filter_dates(filters)
    (filters || {}).to_h do |key, value|
      date = key.to_s.end_with?("_from", "_to") ? (Date.iso8601(value.to_s) rescue nil) : nil
      [ key, date ? date.next_year.iso8601 : value ]
    end
  end

  # The grants whose badges the viewer (a Person) holds; with amounts, only
  # those that show amounts. Any one of them is enough: the people lists here
  # and Accounting::RuleAccess both go through this.
  def grants_held_by(viewer, amounts: false)
    return [] unless viewer && GatherPack::Features.enabled?(:badges)

    badge_ids = viewer.badge_ids
    badge_grants.includes(:badge).select { |grant| badge_ids.include?(grant.badge_id) && (!amounts || grant.amounts?) }
  end

  private
    # The people covered by grants whose badges the viewer holds.
    def granted_people(viewer, amounts: false)
      grants_held_by(viewer, amounts: amounts).map(&:covered_people)
    end

    def generate_key
      return if key.present? || name.blank?

      base = name.delete("'’").parameterize(separator: "_").gsub(/[^a-z0-9]+/, "_").sub(/\A[^a-z]+/, "").delete_suffix("_").presence || "rule"
      candidate = base
      suffix = 1
      candidate = "#{base}_#{suffix += 1}" while AccountingRule.exists?(key: candidate)
      self.key = candidate
    end

    def key_unchanged
      errors.add(:key, "can't be changed once created") if will_save_change_to_key?
    end

    def normalize_settings
      self.settings = (settings || {}).to_h
      self.unapplied_credit = unapplied_credit.presence || "show"
      self.measure = measure.presence || ("invoiced" if kind == "amount")
      self.grace_days = grace_days.presence && (Integer(grace_days.to_s, exception: false) || grace_days)
      self.labels = (labels || {}).to_h.transform_values { |label| label.to_s.strip }.compact_blank.presence
      self.show_pay_links = ActiveModel::Type::Boolean.new.cast(show_pay_links) == true
    end

    # Keeps the known keys, drops blank ones, stores dates as ISO dates and
    # id lists as strings.
    def normalize_filters
      self.filters = (filters || {}).to_h.stringify_keys.slice(*FILTER_KEYS).filter_map do |key, value|
        value = case key
        when "roles", "items", "classes", "locations" then Array(value).map(&:to_s).compact_blank.uniq.presence
        when "min_total" then value.presence && Integer(value.to_s, exception: false)
        else value.presence && (Date.iso8601(value.to_s).iso8601 rescue value.to_s)
        end
        [ key, value ] unless value.nil?
      end.to_h
    end

    def filter_dates_valid
      errors.add(:filters, "have a date that isn't a date") if filters.any? { |key, value| key.end_with?("_from", "_to") && !iso_date?(value) }
      errors.add(:filters, "can't skip records under less than nothing") if filters["min_total"].to_i.negative?
    end

    def iso_date?(value)
      value.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/) && Date.iso8601(value.to_s).present?
    rescue Date::Error
      false
    end

    def source_is_accounting
      errors.add(:gateway, "must be an accounting source") if gateway && !gateway.is_a?(Accounting::Provider)
    end

    # As with forms and person fields, seeing amounts can't reach further
    # than seeing the result.
    def amounts_within_read
      return unless read_permission && amount_permission

      errors.add(:amount_permission, "can't include people who can't see the result") unless AudienceLevels.within?(amount_permission, read_permission)
    end
end
