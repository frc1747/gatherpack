# One piece of a tracked item, with its own label, condition and history
# (inventory spec §3.15). location is where the unit physically is; a unit
# installed in another unit (a motor in a swerve module) also has
# installed_in, and moves with it. A unit is installed when it's in another
# unit or on a machine (a place of kind machine, named as Inventory setup
# says: Inventory.machine_word).
#
# Every change goes through an action method here (install!, take_off!,
# move!, check!, mark_for_repair!, repaired!, retire!, ItemUnit.receive!,
# ItemUnitEvent#undo!), which takes the item's and unit's row locks and
# writes an ItemUnitEvent in the same transaction. Each raises
# Inventory::Refused with a message fit to show; install! raises
# Inventory::ConfirmNeeded for a unit needing repair unless confirm: true.
class ItemUnit < ApplicationRecord
  has_neat_id :unt
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  CONDITIONS = %w[new good worn needs_repair broken retired].freeze
  # Flagged: not available, and asks before installing.
  FLAGGED = %w[needs_repair broken].freeze
  CONDITION_LABELS = {
    "new" => "New", "good" => "Good", "worn" => "Worn",
    "needs_repair" => "Needs repair", "broken" => "Broken", "retired" => "Retired"
  }.freeze
  ACTION_WORDS = {
    install: "install", take_off: "take off", move: "move", check: "check",
    mark_for_repair: "mark for repair", repaired: "mark repaired", retire: "retire"
  }.freeze

  belongs_to :item
  belongs_to :location
  belongs_to :installed_in, class_name: "ItemUnit", optional: true, inverse_of: :contents
  has_many :contents, class_name: "ItemUnit", foreign_key: :installed_in_id, inverse_of: :installed_in,
    dependent: :restrict_with_error
  has_many :events, -> { order(:created_at) }, class_name: "ItemUnitEvent", inverse_of: :item_unit,
    dependent: :restrict_with_error
  has_one_attached :photo

  enum :condition, CONDITIONS.index_by(&:itself), prefix: :condition, default: "new", validate: true

  validate :code_unique_in_team
  validate :item_is_tracked
  validate :not_inside_itself

  before_validation { self.code = code.to_s.strip.presence }
  before_validation(on: :create) { self.in_service_on ||= Date.current }

  scope :active, -> { where(active: true) }
  scope :not_retired, -> { where.not(condition: "retired") }
  scope :flagged, -> { where(condition: FLAGGED) }
  # Spares: active, in an active storage place, not installed, not flagged
  # or retired. The number the reorder list counts for a tracked item.
  scope :available, lambda {
    active.where(installed_in_id: nil).where.not(condition: FLAGGED + [ "retired" ])
      .joins(:location).merge(Location.active.storage)
  }
  scope :installed, -> { joins(:location).where.not(installed_in_id: nil).or(joins(:location).where(locations: { kind: "machine" })) }

  def self.ransackable_attributes(auth_object = nil)
    %w[code serial_number name condition item_id location_id active]
  end

  def identifier_name
    code.presence || name.presence || "#{item&.name} (no code yet)"
  end

  def identifier_icon
    "microchip"
  end

  def condition_label
    CONDITION_LABELS.fetch(condition)
  end

  def flagged?
    FLAGGED.include?(condition)
  end

  def on_machine?
    location.machine?
  end

  def installed?
    installed_in_id.present? || on_machine?
  end

  def available?
    active? && installed_in_id.nil? && !flagged? && !condition_retired? && location.storage? && location.active?
  end

  # Every unit inside this one, at any depth.
  def all_contents
    contents.flat_map { |unit| [ unit ] + unit.all_contents }
  end

  # The newest value of each reading, from the checks: { name => value }.
  def latest_readings
    events.where(action: "check").where.not(readings: {}).each_with_object({}) do |event, latest|
      latest.merge!(event.readings)
    end
  end

  # Creates units of a tracked item at a storage location, as received
  # stock (the counterpart of a received movement), and returns them.
  def self.receive!(item:, location:, count:, person:, note: nil, recorded_by: nil, authorized_by: nil)
    actor = recorded_by || person
    unless authorized_by || Inventory::Access.for(actor).may_record?("received", item, location)
      raise Inventory::Refused, "You can't receive #{item.name} here"
    end
    raise Inventory::Refused, "#{item.name} isn't tracked" unless item.tracked?
    raise Inventory::Refused, "Receive into a storage place, not #{Inventory.machine_word(article: true)}" if location.machine?
    raise Inventory::Refused, "#{location.name} isn't active" unless location.active?

    count = Integer(count.to_s, 10, exception: false)
    raise Inventory::Refused, "The number of units must be a whole number above zero" if count.nil? || count <= 0

    units = []
    announce = ->(crossings, _after) { units.last.last_event.announcement = { item: item, crossings: crossings, hooks: [] } }
    Inventory::Stock.with_crossings(item, announce: announce) do
      count.times do
        units << create_with_event!(item: item, location: location, person: person, recorded_by: recorded_by, note: note, action: "received")
      end
    end
    units
  end

  # The event the last action on this object wrote.
  attr_accessor :last_event

  # A new unit and its first event. No checks: callers check first.
  def self.create_with_event!(item:, location:, person:, recorded_by: nil, note: nil, action: "tracked")
    unit = create!(item: item, location: location)
    unit.last_event = unit.events.create!(action: action, to_location: location, condition_after: unit.condition, person: person,
      recorded_by: (recorded_by if recorded_by != person), note: note.to_s.strip.presence)
    unit
  end

  # Puts the unit on a machine or in another unit; anything inside it goes
  # too. A unit marked Needs repair or Broken needs confirm: true, which the
  # event records. While Inventory setup turns machines off, only another
  # unit can be the target (as ItemUnitPolicy#install? expects).
  def install!(into:, by:, confirm: false, note: nil, recorded_by: nil, authorized_by: nil)
    authorize_action!(:install, by, recorded_by, authorized_by, into)
    raise Inventory::Refused, "A retired unit can't be installed" if condition_retired? || !active?

    if into.is_a?(ItemUnit)
      raise Inventory::Refused, "A unit can't go inside itself" if into.id == id || all_contents.any? { |unit| unit.id == into.id }
      raise Inventory::Refused, "#{into.identifier_name} is retired" if into.condition_retired? || !into.active?

      to_location, to_unit = into.location, into
    else
      unless into.machine?
        raise Inventory::Refused, "Use Move for a storage place" unless Inventory.machines?

        raise Inventory::Refused, "Install it on #{Inventory.machine_word(article: true)}, or use Move for a storage place"
      end
      raise Inventory::Refused, "#{Inventory.machine_word(count: :many, capitalize: true)} are turned off" unless Inventory.machines?
      raise Inventory::Refused, "#{into.name} isn't active" unless into.active?

      to_location, to_unit = into, nil
    end
    raise Inventory::Refused, "It's already there" if location_id == to_location.id && installed_in_id == to_unit&.id
    if flagged? && !confirm
      raise Inventory::ConfirmNeeded, "This unit is marked #{condition_label}: install anyway?"
    end

    relocate!("install", to_location, to_unit, person: by, recorded_by: recorded_by, note: note, confirmed: flagged?)
  end

  # Takes the unit off its machine or out of another unit, back to a
  # storage place (the item's home location unless given).
  def take_off!(by:, to: nil, note: nil, recorded_by: nil, authorized_by: nil)
    to ||= item.home_location
    authorize_action!(:take_off, by, recorded_by, authorized_by, to)
    raise Inventory::Refused, "It isn't installed" unless installed?
    raise Inventory::Refused, "Pick a place to put it" if to.nil?
    raise Inventory::Refused, "Take it off into a storage place" if to.machine?
    raise Inventory::Refused, "#{to.name} isn't active" unless to.active?

    relocate!("take_off", to, nil, person: by, recorded_by: recorded_by, note: note)
  end

  # From one storage place to another.
  def move!(to:, by:, note: nil, recorded_by: nil, authorized_by: nil)
    authorize_action!(:move, by, recorded_by, authorized_by, to)
    raise Inventory::Refused, "It's installed: take it off first" if installed?
    if to.machine?
      raise Inventory::Refused, "#{to.name} isn't a storage place" unless Inventory.machines?

      raise Inventory::Refused, "Use Install to put it on #{Inventory.machine_word(article: true)}"
    end
    raise Inventory::Refused, "It's already there" if to.id == location_id
    raise Inventory::Refused, "#{to.name} isn't active" unless to.active?

    relocate!("move", to, nil, person: by, recorded_by: recorded_by, note: note)
  end

  # Records the condition, a note, an optional photo and any of the item's
  # readings ({ name => number }). Taking a unit out of Needs repair or
  # Broken this way needs the Repaired permission.
  def check!(by:, condition: nil, readings: {}, note: nil, photo: nil, recorded_by: nil, authorized_by: nil)
    authorize_action!(:check, by, recorded_by, authorized_by)
    condition = (condition.presence || self.condition).to_s
    raise Inventory::Refused, "Pick a condition" unless CONDITIONS.include?(condition) && condition != "retired"
    authorize_action!(:repaired, by, recorded_by, authorized_by) if flagged? && !FLAGGED.include?(condition)
    refuse_retired!

    change_condition!("check", condition, person: by, recorded_by: recorded_by, note: note, photo: photo,
      readings: clean_readings(readings))
  end

  def mark_for_repair!(by:, note:, condition: "needs_repair", recorded_by: nil, authorized_by: nil)
    authorize_action!(:mark_for_repair, by, recorded_by, authorized_by)
    refuse_retired!
    raise Inventory::Refused, "Say what's wrong" if note.blank?
    raise Inventory::Refused, "Pick Needs repair or Broken" unless FLAGGED.include?(condition.to_s)

    change_condition!("mark_for_repair", condition.to_s, person: by, recorded_by: recorded_by, note: note)
  end

  def repaired!(by:, note:, condition: "good", recorded_by: nil, authorized_by: nil)
    authorize_action!(:repaired, by, recorded_by, authorized_by)
    raise Inventory::Refused, "It isn't marked for repair" unless flagged?
    raise Inventory::Refused, "Say what was done" if note.blank?
    raise Inventory::Refused, "Pick Good or Worn" unless condition.to_s.in?(%w[good worn])

    change_condition!("repaired", condition.to_s, person: by, recorded_by: recorded_by, note: note)
  end

  def retire!(by:, note:, recorded_by: nil, authorized_by: nil)
    authorize_action!(:retire, by, recorded_by, authorized_by)
    refuse_retired!
    raise Inventory::Refused, "It's installed: take it off first" if installed?
    raise Inventory::Refused, "Say why" if note.blank?

    change_condition!("retire", "retired", person: by, recorded_by: recorded_by, note: note)
  end

  # Moves the unit, and everything inside it, to a location and outer unit,
  # writing an event for each. Used by the actions and by undo; no checks.
  def relocate!(action, to_location, to_unit, person:, recorded_by: nil, note: nil, confirmed: false, reverses: nil)
    event = nil
    hooks = []
    announce = ->(crossings, _after) { event.announcement = { item: item, crossings: crossings, hooks: hooks.select(&:first) } }
    Inventory::Stock.with_crossings(item, announce: announce) do
      lock!
      hooks << [ placement_hook(location, to_location), self ]
      event = events.create!(action: action, from_location: location, to_location: to_location, from_unit: installed_in,
        to_unit: to_unit, condition_before: condition, condition_after: condition, person: person,
        recorded_by: (recorded_by if recorded_by != person), note: note.to_s.strip.presence, confirmed: confirmed, reverses: reverses)
      inner = all_contents
      update!(location: to_location, installed_in: to_unit)
      inner.each do |unit|
        hooks << [ placement_hook(unit.location, to_location), unit ]
        unit.events.create!(action: action, from_location: unit.location, to_location: to_location, from_unit: unit.installed_in,
          to_unit: unit.installed_in, via_unit: self, condition_before: unit.condition, condition_after: unit.condition,
          person: person, recorded_by: (recorded_by if recorded_by != person), reverses: reverses && reverses_for(reverses, unit))
        unit.update!(location: to_location)
      end
    end
    event
  end

  # Sets the condition and writes the event. Used by the actions and by
  # undo; no checks.
  def change_condition!(action, new_condition, person:, recorded_by: nil, note: nil, photo: nil, readings: {}, reverses: nil)
    event = nil
    hooks = []
    announce = ->(crossings, _after) { event.announcement = { item: item, crossings: crossings, hooks: hooks } }
    Inventory::Stock.with_crossings(item, announce: announce) do
      lock!
      before = condition
      event = events.create!(action: action, from_location: location, to_location: location, condition_before: before,
        condition_after: new_condition, readings: readings, person: person, recorded_by: (recorded_by if recorded_by != person),
        note: note.to_s.strip.presence, reverses: reverses, photo: photo.presence)
      update!(condition: new_condition, condition_note: note.to_s.strip.presence || condition_note)
      hooks << [ Inventory::UNIT_EVENTS[:needs_repair], self ] if FLAGGED.include?(new_condition) && !FLAGGED.include?(before)
    end
    event
  end

  private

  def authorize_action!(action, by, recorded_by, authorized_by, target = nil)
    return if authorized_by
    return if Inventory::Access.for(recorded_by || by).may_unit_action?(action, self, target)

    raise Inventory::Refused, "You can't #{ACTION_WORDS.fetch(action)} this unit"
  end

  def refuse_retired!
    raise Inventory::Refused, "This unit is retired" if condition_retired?
  end

  # installed or removed when a move puts the unit onto or takes it off a
  # machine, else nil.
  def placement_hook(from, to)
    return Inventory::UNIT_EVENTS[:installed] if !from.machine? && to.machine?

    Inventory::UNIT_EVENTS[:removed] if from.machine? && !to.machine?
  end

  # The carried event (for an inner unit) that an undone outer event moved.
  def reverses_for(outer_event, unit)
    ItemUnitEvent.where(item_unit_id: unit.id, via_unit_id: id, created_at: outer_event.created_at..).order(:created_at).first
  end

  def clean_readings(readings)
    names = item.reading_names
    (readings || {}).to_h.each_with_object({}) do |(name, value), clean|
      next if value.to_s.strip.empty?
      raise Inventory::Refused, "#{name} isn't a reading for #{item.name}" unless names.include?(name.to_s)

      number = Float(value.to_s.strip, exception: false)
      raise Inventory::Refused, "#{name} must be a number" if number.nil?

      clean[name.to_s] = number == number.to_i ? number.to_i : number
    end
  end

  def code_unique_in_team
    return if code.blank? || item.nil?

    clash = ItemUnit.joins(:item).where(items: { team_id: item.team_id })
      .where("LOWER(item_units.code) = ?", code.downcase).where.not(id: id).exists?
    errors.add(:code, "is already used by another unit") if clash
  end

  def item_is_tracked
    errors.add(:item, "isn't tracked") if item && !item.tracked? && new_record?
  end

  def not_inside_itself
    return if installed_in_id.nil?

    errors.add(:installed_in, "can't be the unit itself") if installed_in_id == id
  end
end
