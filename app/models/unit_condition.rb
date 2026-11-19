# A condition a tracked unit can be in (inventory spec §3.15), managed on
# Setup: New, Good, Worn, Needs repair, Broken, Retired. Code reads the
# flags, never the name: needs_attention conditions take a unit out of the
# spares and ask before installing it; out_of_service ones take it out of
# every count and end its use. The actions pick a condition by key first
# (needs_repair, good, retired, new for new units) so renaming a default
# keeps working, and fall back to the first active row with the same flags.
class UnitCondition < ApplicationRecord
  include ManagedList
  has_neat_id :ucnd
  managed_list uses: { item_units: :unit_condition_id }

  # Columns of the unit history that point here too. History is never
  # edited, so a merge repoints them in SQL rather than through the model.
  HISTORY_COLUMNS = %i[condition_before_id condition_after_id].freeze

  has_many :item_units, dependent: :restrict_with_error

  validate :one_flag

  before_destroy :keep_history, prepend: true

  scope :in_use, -> { where(out_of_service: false) }
  scope :working, -> { where(needs_attention: false, out_of_service: false) }
  scope :attention, -> { where(needs_attention: true) }

  # Conditions a check can record: every active one that isn't out of service.
  def self.for_check
    active.in_use.ordered
  end

  # Conditions Mark for repair offers.
  def self.for_repair
    active.attention.ordered
  end

  # Conditions Repaired offers.
  def self.after_repair
    active.working.ordered
  end

  # The condition an action sets: the row with the key while it's active,
  # else the first active row of the scope.
  def self.pick(key, scope)
    Inventory::Lists.seed!(UnitCondition)
    active.find_by(key: key) || scope.first
  end

  def self.for_new_units
    pick("new", active.working.ordered) or raise Inventory::Refused, "Add a working part condition on Setup first"
  end

  def self.needs_repair
    pick("needs_repair", for_repair) or raise Inventory::Refused, "Add a part condition that needs attention on Setup first"
  end

  def self.repaired
    pick("good", after_repair) or raise Inventory::Refused, "Add a working part condition on Setup first"
  end

  def self.retire_condition
    pick("retired", active.where(out_of_service: true).ordered) or
      raise Inventory::Refused, "Add an out of service part condition on Setup first"
  end

  # A condition by id, neat id or key (tools may send "needs_repair"), or
  # nil.
  def self.resolve(value)
    return value if value.is_a?(UnitCondition)
    return nil if value.blank?

    text = value.to_s
    find_by(id: text) || find_by(key: text) || (NeatIds.find(text) rescue nil).then { |row| row if row.is_a?(UnitCondition) }
  end

  def in_history?
    HISTORY_COLUMNS.any? { |column| ItemUnitEvent.where(column => id).exists? }
  end

  def in_use?
    super || in_history?
  end

  def merge_into!(other)
    transaction do
      HISTORY_COLUMNS.each { |column| ItemUnitEvent.where(column => id).update_all(column => other.id) }
      super
    end
  end

  private

  def one_flag
    errors.add(:base, "A condition can need attention or be out of service, not both") if needs_attention? && out_of_service?
  end

  def keep_history
    return if key.present? || !in_history?

    errors.add(:base, "#{name} is in units' history, so it can't be deleted. Retire it or merge it into another one.")
    throw :abort
  end
end
