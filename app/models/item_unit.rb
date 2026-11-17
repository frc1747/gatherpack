# One piece of a tracked item, with its own label, condition and history
# (inventory spec §3.15). location is where the unit physically is; a unit
# installed in another unit (a motor in a swerve module) also has
# installed_in, and moves with it. A unit is installed when it's in another
# unit or on a machine (a place whose type holds installed parts). Its
# condition is a UnitCondition (a list managed on Setup); the code reads
# the condition's flags, never its name.
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

  ACTION_WORDS = {
    install: "install", take_off: "take off", move: "move", check: "check",
    mark_for_repair: "mark for repair", repaired: "mark repaired", retire: "retire"
  }.freeze

  belongs_to :item
  belongs_to :location
  belongs_to :unit_condition
  belongs_to :installed_in, class_name: "ItemUnit", optional: true, inverse_of: :contents
  has_many :contents, class_name: "ItemUnit", foreign_key: :installed_in_id, inverse_of: :installed_in,
    dependent: :restrict_with_error
  has_many :events, -> { order(:created_at) }, class_name: "ItemUnitEvent", inverse_of: :item_unit,
    dependent: :restrict_with_error
  has_one_attached :photo

  validate :code_unique_in_team
  validate :item_is_tracked
  validate :not_inside_itself

  before_validation { self.code = code.to_s.strip.presence }
  before_validation(on: :create) { self.in_service_on ||= Date.current }
  before_validation(on: :create) { self.unit_condition ||= UnitCondition.for_new_units }

  scope :active, -> { where(active: true) }
  scope :not_retired, -> { where(unit_condition_id: UnitCondition.in_use.select(:id)) }
  # Flagged: in a condition that needs attention.
  scope :flagged, -> { where(unit_condition_id: UnitCondition.attention.select(:id)) }
  # Spares: active, in an active place that keeps stock, not installed, in a
  # working condition. The number the reorder list counts for a tracked item.
  scope :available, lambda {
    active.where(installed_in_id: nil, unit_condition_id: UnitCondition.working.select(:id))
      .where(location_id: Location.active.storage.select(:id))
  }
  scope :installed, -> { where.not(installed_in_id: nil).or(where(location_id: Location.machine.select(:id))) }

  def self.ransackable_attributes(auth_object = nil)
    %w[code serial_number name unit_condition_id item_id location_id active]
  end

  def identifier_name
    code.presence || name.presence || "#{item&.name} (no code yet)"
  end

  def identifier_icon
    "microchip"
  end

  def condition_label
    unit_condition&.name
  end

  # In a condition that needs attention (Needs repair, Broken): not a spare,
  # and installing it asks first.
  def flagged?
    unit_condition&.needs_attention? || false
  end

  # In a condition that ends its use (Retired).
  def out_of_service?
    unit_condition&.out_of_service? || false
  end

  def on_machine?
    location.machine?
  end

  def installed?
    installed_in_id.present? || on_machine?
  end

  def available?
    active? && installed_in_id.nil? && !flagged? && !out_of_service? && location.storage? && location.active?
  end

  # Every unit inside this one, at any depth.
  def all_contents
    contents.flat_map { |unit| [ unit ] + unit.all_contents }
  end

  # The newest value of each reading, from the checks: { reading type id =>
  # value }.
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
    raise Inventory::Refused, "Receive into a place that keeps stock, not #{location.type_word(article: true)}" unless location.storage?
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
    unit.last_event = unit.events.create!(action: action, to_location: location, condition_after: unit.unit_condition, person: person,
      recorded_by: (recorded_by if recorded_by != person), note: note.to_s.strip.presence)
    unit
  end

  # Puts the unit on a machine or in another unit; anything inside it goes
  # too. A unit in a condition that needs attention needs confirm: true,
  # which the event records. A place whose type is retired takes no parts;
  # with no type taking them, only another unit can be the target (as
  # ItemUnitPolicy#install? expects).
  def install!(into:, by:, confirm: false, note: nil, recorded_by: nil, authorized_by: nil)
    authorize_action!(:install, by, recorded_by, authorized_by, into)
    raise Inventory::Refused, "A retired unit can't be installed" if out_of_service? || !active?

    if into.is_a?(ItemUnit)
      raise Inventory::Refused, "A unit can't go inside itself" if into.id == id || all_contents.any? { |unit| unit.id == into.id }
      raise Inventory::Refused, "#{into.identifier_name} is retired" if into.out_of_service? || !into.active?

      to_location, to_unit = into.location, into
    else
      unless into.machine?
        raise Inventory::Refused, "Use Move for a storage place" unless LocationType.installable.exists?

        raise Inventory::Refused, "Install it on #{LocationType.installable_words}, or use Move for a storage place"
      end
      raise Inventory::Refused, "#{into.location_type.plural_name} are retired" unless into.takes_installs?
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
    raise Inventory::Refused, "Take it off into a place that keeps stock" unless to.storage?
    raise Inventory::Refused, "#{to.name} isn't active" unless to.active?

    relocate!("take_off", to, nil, person: by, recorded_by: recorded_by, note: note)
  end

  # From one storage place to another.
  def move!(to:, by:, note: nil, recorded_by: nil, authorized_by: nil)
    authorize_action!(:move, by, recorded_by, authorized_by, to)
    raise Inventory::Refused, "It's installed: take it off first" if installed?
    unless to.storage?
      raise Inventory::Refused, "Use Install to put it on #{to.type_word(article: true)}" if to.takes_installs?

      raise Inventory::Refused, "#{to.name} isn't a place that keeps stock"
    end
    raise Inventory::Refused, "It's already there" if to.id == location_id
    raise Inventory::Refused, "#{to.name} isn't active" unless to.active?

    relocate!("move", to, nil, person: by, recorded_by: recorded_by, note: note)
  end

  # Records the condition, a note, an optional photo and any of the item's
  # readings ({ reading type id or name => number }). A condition is a
  # UnitCondition, its id or its key; none keeps the current one. Taking a
  # unit out of a condition that needs attention this way needs the
  # Repaired permission.
  def check!(by:, condition: nil, readings: {}, note: nil, photo: nil, recorded_by: nil, authorized_by: nil)
    authorize_action!(:check, by, recorded_by, authorized_by)
    condition = condition.present? ? UnitCondition.resolve(condition) : unit_condition
    unless condition && !condition.out_of_service? && (condition.active? || condition == unit_condition)
      raise Inventory::Refused, "Pick a condition"
    end
    authorize_action!(:repaired, by, recorded_by, authorized_by) if flagged? && !condition.needs_attention?
    refuse_retired!

    change_condition!("check", condition, person: by, recorded_by: recorded_by, note: note, photo: photo,
      readings: clean_readings(readings))
  end

  # Sets a condition that needs attention: the one given, or Needs repair.
  def mark_for_repair!(by:, note:, condition: nil, recorded_by: nil, authorized_by: nil)
    authorize_action!(:mark_for_repair, by, recorded_by, authorized_by)
    refuse_retired!
    raise Inventory::Refused, "Say what's wrong" if note.blank?

    condition = condition.present? ? UnitCondition.resolve(condition) : UnitCondition.needs_repair
    unless condition&.active? && condition.needs_attention?
      raise Inventory::Refused, "Pick #{condition_choices(UnitCondition.for_repair)}"
    end

    change_condition!("mark_for_repair", condition, person: by, recorded_by: recorded_by, note: note)
  end

  # Sets a working condition: the one given, or Good.
  def repaired!(by:, note:, condition: nil, recorded_by: nil, authorized_by: nil)
    authorize_action!(:repaired, by, recorded_by, authorized_by)
    raise Inventory::Refused, "It isn't marked for repair" unless flagged?
    raise Inventory::Refused, "Say what was done" if note.blank?

    condition = condition.present? ? UnitCondition.resolve(condition) : UnitCondition.repaired
    unless condition&.active? && !condition.needs_attention? && !condition.out_of_service?
      raise Inventory::Refused, "Pick #{condition_choices(UnitCondition.after_repair)}"
    end

    change_condition!("repaired", condition, person: by, recorded_by: recorded_by, note: note)
  end

  def retire!(by:, note:, recorded_by: nil, authorized_by: nil)
    authorize_action!(:retire, by, recorded_by, authorized_by)
    refuse_retired!
    raise Inventory::Refused, "It's installed: take it off first" if installed?
    raise Inventory::Refused, "Say why" if note.blank?

    change_condition!("retire", UnitCondition.retired, person: by, recorded_by: recorded_by, note: note)
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
        to_unit: to_unit, condition_before: unit_condition, condition_after: unit_condition, person: person,
        recorded_by: (recorded_by if recorded_by != person), note: note.to_s.strip.presence, confirmed: confirmed, reverses: reverses)
      inner = all_contents
      update!(location: to_location, installed_in: to_unit)
      inner.each do |unit|
        hooks << [ placement_hook(unit.location, to_location), unit ]
        unit.events.create!(action: action, from_location: unit.location, to_location: to_location, from_unit: unit.installed_in,
          to_unit: unit.installed_in, via_unit: self, condition_before: unit.unit_condition, condition_after: unit.unit_condition,
          person: person, recorded_by: (recorded_by if recorded_by != person), reverses: reverses && reverses_for(reverses, unit))
        unit.update!(location: to_location)
      end
    end
    event
  end

  # Sets the condition (a UnitCondition) and writes the event. Used by the
  # actions and by undo; no checks.
  def change_condition!(action, new_condition, person:, recorded_by: nil, note: nil, photo: nil, readings: {}, reverses: nil)
    event = nil
    hooks = []
    announce = ->(crossings, _after) { event.announcement = { item: item, crossings: crossings, hooks: hooks } }
    Inventory::Stock.with_crossings(item, announce: announce) do
      lock!
      before = unit_condition
      event = events.create!(action: action, from_location: location, to_location: location, condition_before: before,
        condition_after: new_condition, readings: readings, person: person, recorded_by: (recorded_by if recorded_by != person),
        note: note.to_s.strip.presence, reverses: reverses, photo: photo.presence)
      update!(unit_condition: new_condition, condition_note: note.to_s.strip.presence || condition_note)
      hooks << [ Inventory::UNIT_EVENTS[:needs_repair], self ] if new_condition&.needs_attention? && !before&.needs_attention?
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
    raise Inventory::Refused, "This unit is retired" if out_of_service?
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

  # "Needs repair or Broken": the conditions an action offers.
  def condition_choices(scope)
    names = scope.map(&:name)
    names.any? ? names.to_sentence(two_words_connector: " or ", last_word_connector: " or ") : "a condition"
  end

  # { reading type id => number } for the item's reading types, given by
  # id, neat id or name.
  def clean_readings(readings)
    types = item.reading_types.to_a
    (readings || {}).to_h.each_with_object({}) do |(key, value), clean|
      next if value.to_s.strip.empty?

      key = key.to_s
      type = types.find { |candidate| candidate.id == key || candidate.neat_id == key || candidate.name.casecmp?(key) }
      raise Inventory::Refused, "#{key} isn't a reading for #{item.name}" unless type

      number = Float(value.to_s.strip, exception: false)
      raise Inventory::Refused, "#{type.name} must be a number" if number.nil?

      clean[type.id] = number == number.to_i ? number.to_i : number
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
