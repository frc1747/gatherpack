# A unit stock is counted in (inventory spec §3.1), managed on Setup: each,
# box, foot. Exactly one active row is the default, which new items start
# with; making another row the default takes it from the old one.
class StockUnit < ApplicationRecord
  include ManagedList
  has_neat_id :stun
  managed_list uses: { items: :stock_unit_id }

  has_many :items, dependent: :restrict_with_error

  validate :default_stays_somewhere
  validate :default_is_active

  before_save :take_default, if: -> { default? && will_save_change_to_default? }

  # The unit new items start with.
  def self.default_unit
    find_by(default: true) || active.ordered.first
  end

  # The row a typed unit names, by name or plural, ignoring case: "ft" or
  # "Feet". Nil when none does.
  def self.named(text)
    text = text.to_s.strip.downcase
    return nil if text.empty?

    where("LOWER(name) = :t OR LOWER(plural) = :t", t: text).order(active: :desc, position: :asc).first
  end

  # "3 boxes", "1 box", or just "3" in the each unit.
  def quantity_text(quantity)
    return quantity.to_s if key == "each"

    "#{quantity} #{quantity.to_i.abs == 1 ? name : plural_name}"
  end

  private

  def take_default
    StockUnit.where.not(id: id).where(default: true).update_all(default: false, updated_at: Time.current)
  end

  def default_stays_somewhere
    return unless persisted? && will_save_change_to_default? && !default?

    errors.add(:default, "can't be turned off here: make another unit the default instead")
  end

  def default_is_active
    errors.add(:active, "can't be turned off for the default unit: make another unit the default first") if default? && !active?
  end
end
