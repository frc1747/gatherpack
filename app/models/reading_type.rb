# Something a check can record on a tracked unit (inventory spec §3.15),
# managed on Setup: Hours (h), Cycles, Volts (V). Items pick the ones their
# checks ask for (ItemReadingType). Readings stored on a check are keyed by
# the type's id, so renaming one renames it in every history.
class ReadingType < ApplicationRecord
  include ManagedList
  has_neat_id :rdty
  managed_list uses: { item_reading_types: :reading_type_id }

  has_many :item_reading_types, dependent: :restrict_with_error

  before_validation { self.unit_label = unit_label.to_s.strip.presence }
  before_destroy :keep_readings, prepend: true

  # "Hours (h)", or "Cycles"; a name that already ends with its unit in
  # brackets isn't given it twice.
  def heading
    return name if unit_label.blank? || name.end_with?("(#{unit_label})")

    "#{name} (#{unit_label})"
  end

  def in_readings?
    ItemUnitEvent.where("readings ? :id", id: id).exists?
  end

  def in_use?
    super || in_readings?
  end

  # Items that tracked both keep one link; readings stored under this type
  # move to the other.
  def merge_into!(other)
    transaction do
      ItemReadingType.where(reading_type_id: id, item_id: ItemReadingType.where(reading_type_id: other.id).select(:item_id)).delete_all
      ItemUnitEvent.where("readings ? :id", id: id).update_all([
        "readings = (readings - :id) || jsonb_build_object(:other, readings -> :id)", { id: id, other: other.id }
      ])
      super
    end
  end

  private

  def keep_readings
    return unless in_readings?

    errors.add(:base, "#{name} has readings saved on checks, so it can't be deleted. Retire it or merge it into another one.")
    throw :abort
  end
end
