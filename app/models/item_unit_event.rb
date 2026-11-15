# One entry in a unit's history (inventory spec §3.15): who did what, from
# where to where, the condition before and after, and any readings.
# Written by the ItemUnit actions in the same transaction as the change.
# Entries are never edited or deleted, by anyone: an undo writes a
# reversing event (reverses_id). via_unit is the outer unit an inner unit
# moved with; confirmed records "install anyway" for a unit needing repair.
class ItemUnitEvent < ApplicationRecord
  has_neat_id :uev
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }, on: %i[create]

  ACTIONS = %w[install take_off move check mark_for_repair repaired retire received tracked].freeze
  # Actions that move the unit, and those that change its condition.
  RELOCATIONS = %w[install take_off move].freeze
  UNDOABLE = Inventory::Config::UNIT_ACTIONS

  belongs_to :item_unit, inverse_of: :events
  belongs_to :from_location, class_name: "Location", optional: true
  belongs_to :to_location, class_name: "Location", optional: true
  belongs_to :from_unit, class_name: "ItemUnit", optional: true
  belongs_to :to_unit, class_name: "ItemUnit", optional: true
  belongs_to :via_unit, class_name: "ItemUnit", optional: true
  belongs_to :person, optional: true
  belongs_to :recorded_by, class_name: "Person", optional: true
  belongs_to :reverses, class_name: "ItemUnitEvent", optional: true
  has_one :reversal, class_name: "ItemUnitEvent", foreign_key: :reverses_id, inverse_of: :reverses, dependent: nil
  has_one_attached :photo

  validates :action, inclusion: { in: ACTIONS }

  # What the action worked out for hooks, run once the transaction commits.
  attr_accessor :announcement

  after_create_commit :announce

  before_destroy { raise ActiveRecord::ReadOnlyRecord, "Unit history can't be deleted" }

  def self.ransackable_attributes(auth_object = nil)
    %w[action item_unit_id person_id created_at]
  end

  def readonly?
    persisted? || super
  end

  # delete skips callbacks and the readonly check, so refuse it here too.
  def delete
    raise ActiveRecord::ReadOnlyRecord, "Unit history can't be deleted"
  end

  def identifier_name
    "#{action.humanize} #{item_unit&.identifier_name}"
  end

  def identifier_icon
    "clock-rotate-left"
  end

  def recorder_id
    recorded_by_id || person_id
  end

  def reversal?
    reverses_id.present?
  end

  def undone?
    ItemUnitEvent.exists?(reverses_id: id)
  end

  def carried?
    via_unit_id.present?
  end

  # The unit's own actions, not ones it was carried along by, can be undone
  # while they're its latest: by the recorder within inventory_undo_minutes,
  # and by managers of the item's team at any time.
  def undoable_by?(person, at: Time.current)
    return false if person.nil? || reversal? || undone? || carried? || !UNDOABLE.include?(action)
    return false unless latest?

    access = Inventory::Access.for(person)
    return true if access.manages?(item_unit.item.team_id)

    recorder_id == person.id && access.sees?(item_unit.item) && created_at > at - Inventory::Config.undo_minutes.minutes
  end

  # Puts the unit back as it was before this event, with a reversing event
  # of the same action. Returns the reversing event.
  def undo!(by:, recorded_by: nil)
    raise Inventory::Refused, "This can't be undone" unless undoable_by?(recorded_by || by)

    unit = item_unit
    unit.item.transaction do
      # Checked again under the item's and unit's locks (the action takes
      # the same ones), so two undos at once can't both write a reversal.
      unit.item.lock!
      unit.lock!
      raise Inventory::Refused, "This has already been undone" if ItemUnitEvent.exists?(reverses_id: id)
      raise Inventory::Refused, "This can't be undone" unless latest?

      reverse!(unit, by, recorded_by)
    end
  end

  private

  def latest?
    ItemUnitEvent.where(item_unit_id: item_unit_id).order(created_at: :desc, id: :desc).pick(:id) == id
  end

  def reverse!(unit, by, recorded_by)
    if RELOCATIONS.include?(action)
      outer = from_unit if from_unit&.active? && !from_unit.condition_retired?
      unit.relocate!(action, outer ? outer.location : from_location, outer, person: by, recorded_by: recorded_by,
        note: "Undo", reverses: self)
    else
      unit.change_condition!(action, condition_before, person: by, recorded_by: recorded_by, note: "Undo", reverses: self)
    end
  end

  def announce
    return if announcement.nil?

    Array(announcement[:hooks]).each { |event, unit| Inventory.run_hooks(event, unit) }
    Inventory::Stock.announce_crossings(announcement[:item], Array(announcement[:crossings]))
  end
end
