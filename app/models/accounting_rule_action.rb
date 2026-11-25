# Something a rule does for each person while a condition on their result
# holds: gives them a badge, or writes into one of their person fields
# (Accounting::RuleActions applies them after each evaluation). The
# condition is blank (always), { "values" => [...] } (the result's value is
# one of these), or { "op" =>, "amount_cents" => } / { "op" =>, "count" => }
# (the amount, or a count rule's count, compared). No hooks: a settings row,
# whose changes show in the audit log with its rule.
class AccountingRuleAction < ApplicationRecord
  has_neat_id :ara
  has_paper_trail versions: { class_name: "AuditLog" }

  ACTIONS = %w[ badge person_field ].freeze
  ACTION_NAMES = { "badge" => "Give a badge", "person_field" => "Fill in a person field" }.freeze
  # What a person field action writes: the status in the rule's words, the
  # status word itself, or the amount (a count rule's count).
  WRITES = %w[ label value amount ].freeze
  WRITE_NAMES = { "label" => "The status, in this rule's words", "value" => "The status word (paid, overdue...)", "amount" => "The amount (a count rule's count)" }.freeze
  CONDITION_TYPES = %w[ always values amount count ].freeze
  CONDITION_NAMES = { "always" => "Always", "values" => "The status is one of", "amount" => "The amount is", "count" => "The count is" }.freeze
  OPS = { "lt" => "less than", "lte" => "at most", "eq" => "exactly", "gte" => "at least", "gt" => "more than" }.freeze
  # Field types a value can be written into; integer fields take only the
  # amount, in whole dollars (or the count).
  TEXT_TYPES = %w[ string text select ].freeze

  belongs_to :rule, class_name: "AccountingRule", inverse_of: :actions
  belongs_to :badge, optional: true
  belongs_to :person_field, optional: true

  before_validation :build_condition
  before_validation :drop_unused_targets

  validates :action, inclusion: { in: ACTIONS }
  validates :badge, presence: true, if: :badge?
  validates :person_field, presence: true, if: :person_field?
  validates :write, inclusion: { in: WRITES }, if: :person_field?
  validate :condition_complete
  validate :field_can_take_value
  validate :one_badge_action
  validate :badge_is_admin_assigned
  validate :field_not_written_by_another_rule

  scope :ordered, -> { order(:position, :created_at) }

  def self.field_taken_message(field, rule)
    "#{field.name} is already filled in by the rule #{rule.name}. Two rules filling in one field would keep overwriting each other: " \
      "turn that rule off or remove its action first."
  end

  def badge?
    action == "badge"
  end

  def person_field?
    action == "person_field"
  end

  # Whether the condition holds for a saved result.
  def holds?(result)
    case condition_type
    when "always" then true
    when "values" then condition_values.include?(result.value)
    when "amount" then compare(result.amount_cents, condition["amount_cents"])
    when "count" then compare(result.detail(:count), condition["count"])
    end
  end

  # What a person field action writes for a result: nil clears the field.
  def value_for(result)
    case write
    when "label" then result.label.presence
    when "value" then result.value
    when "amount" then amount_for(result)
    end
  end

  # The form's warning: people other than admins can change the field, so
  # what the rule writes may be overwritten until the next evaluation.
  def field_writable_by_others?
    person_field? && person_field.present? && !person_field.write_admin?
  end

  def description
    what = badge? ? "Give #{badge&.name}" : "Write #{WRITE_NAMES.fetch(write.to_s, write.to_s).downcase} into #{person_field&.name}"
    condition_type == "always" ? what : "#{what} when #{condition_text}"
  end

  # The form's fields, read back from condition.
  def condition_type
    return @condition_type if @condition_type
    return "always" if condition.blank?
    return "values" if condition.key?("values")

    condition.key?("count") ? "count" : "amount"
  end

  def condition_type=(type)
    @condition_type = type.to_s.presence
  end

  def condition_values
    @condition_values || Array(condition&.fetch("values", nil))
  end

  def condition_values=(values)
    @condition_values = Array(values).map { |value| value.to_s.strip }.compact_blank
  end

  # Custom rules' values, typed in, separated by commas.
  def condition_values_text
    condition_values.join(", ")
  end

  def condition_values_text=(text)
    @condition_values = (@condition_values || []) | text.to_s.split(",").map(&:strip).compact_blank
  end

  def condition_op
    @condition_op || condition&.fetch("op", nil)
  end

  def condition_op=(op)
    @condition_op = op.to_s.presence
  end

  def condition_amount
    @condition_amount || (condition && condition["amount_cents"] && Money.new(condition["amount_cents"]).to_s)
  end

  def condition_amount=(text)
    @condition_amount = text.to_s.strip
  end

  def condition_count
    @condition_count || condition&.fetch("count", nil)
  end

  def condition_count=(text)
    @condition_count = text.to_s.strip
  end

  # Other turned-on rules whose actions give the same badge. Allowed (each
  # rule takes back only what it gave, so the person keeps the badge while
  # either condition holds), but the Actions tab says so.
  def other_rules_giving_badge
    return AccountingRule.none unless badge? && badge_id

    AccountingRule.enabled.where.not(id: rule_id).where(id: AccountingRuleAction.where(action: "badge", badge_id: badge_id).select(:rule_id))
  end

  # The turned-on rule, other than this one's, that already fills in the
  # same person field.
  def rule_writing_same_field
    return unless person_field? && person_field_id

    AccountingRule.enabled.where.not(id: rule_id).ordered
      .find_by(id: AccountingRuleAction.where(action: "person_field", person_field_id: person_field_id).select(:rule_id))
  end

  def identifier_name
    "#{rule&.name}: #{description}"
  end

  private
    def amount_for(result)
      return result.detail(:count)&.to_i if rule.kind == "count"
      return nil if result.amount_cents.nil?

      person_field&.type_integer? ? (result.amount_cents / 100.0).round : Money.new(result.amount_cents).to_s
    end

    def compare(actual, limit)
      return false if actual.nil? || limit.nil?

      actual = actual.to_i
      case condition["op"]
      when "lt" then actual < limit
      when "lte" then actual <= limit
      when "eq" then actual == limit
      when "gte" then actual >= limit
      when "gt" then actual > limit
      else false
      end
    end

    def condition_text
      case condition_type
      when "values" then "the status is #{condition_values.map { |value| rule.label_for(value) }.to_sentence(two_words_connector: " or ", last_word_connector: " or ")}"
      when "amount" then "the amount is #{OPS[condition["op"]]} #{Money.new(condition["amount_cents"].to_i).format}"
      when "count" then "the count is #{OPS[condition["op"]]} #{condition["count"]}"
      end
    end

    # Turns the form's fields into the stored condition, when the form gave
    # them.
    def build_condition
      return if @condition_type.nil? && @condition_values.nil? && @condition_op.nil?

      self.condition = case condition_type
      when "values" then { "values" => condition_values.uniq }
      when "amount" then { "op" => condition_op, "amount_cents" => Accounting.parse_cents(@condition_amount || condition_amount) }
      when "count" then { "op" => condition_op, "count" => Integer((@condition_count || condition_count).to_s, 10, exception: false) }
      else {}
      end
    end

    # A badge action keeps no field settings, and a field action no badge.
    def drop_unused_targets
      if badge?
        self.person_field_id = nil
        self.write = nil
      elsif person_field?
        self.badge_id = nil
      end
    end

    # A badge people can give themselves (or managers can give) would be
    # kept for good once given by hand, since a rule never removes a hand-made
    # assignment; so, as with access grants, only badges admins assign.
    def badge_is_admin_assigned
      errors.add(:badge, "must be one only admins can assign") if badge? && badge && !badge.added_by_admin?
    end

    # Two turned-on rules filling in one field would overwrite each other on
    # every run. A turned-off rule (such as a fresh Duplicate) is checked
    # when it's turned on (AccountingRule#fields_written_once).
    def field_not_written_by_another_rule
      return unless rule&.enabled? && (other = rule_writing_same_field)

      errors.add(:base, AccountingRuleAction.field_taken_message(person_field, other))
    end

    def condition_complete
      errors.add(:condition, "has a choice that isn't one") unless CONDITION_TYPES.include?(condition_type)
      case condition_type
      when "values"
        errors.add(:condition, "needs at least one status") if condition_values.empty?
      when "amount", "count"
        errors.add(:condition, "needs a comparison") unless OPS.key?(condition["op"])
        errors.add(:condition, "needs #{condition_type == "amount" ? "an amount" : "a number"}") if condition[condition_type == "amount" ? "amount_cents" : "count"].nil?
      end
    end

    def field_can_take_value
      return unless person_field? && person_field

      if person_field.system_read_only? || person_field.archived?
        errors.add(:person_field, "can't be written by a rule")
      elsif person_field.type_integer?
        errors.add(:write, "into a whole-number field can only be the amount") unless write == "amount"
      elsif !TEXT_TYPES.include?(person_field.data_type)
        errors.add(:person_field, "must be a text, choice or whole-number field")
      end
    end

    # Each result records one badge assignment, so a rule gives at most one
    # badge.
    def one_badge_action
      return unless badge? && rule

      others = rule.actions.reject { |other| other.equal?(self) || (persisted? && other.id == id) || other.marked_for_destruction? || !other.badge? }
      errors.add(:base, "A rule can give only one badge") if others.any?
    end
end
