# A place things are kept, nested: shop › cabinet › bin (inventory spec
# §3.1). A location can hold stock and other locations at the same time.
# Its type (LocationType, a list managed on Setup) says what it does: a
# type that holds_stock keeps counted stock and spare units; on a type that
# holds_installed_parts (a machine, in code: something built and run) only
# units go, and it's either a top-level place or sits under one that isn't
# a machine. While a machine type is retired no place takes it on and no
# part is installed on its places; those already made keep their type.
class Location < ApplicationRecord
  has_neat_id :loc
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :team
  belongs_to :location_type
  belongs_to :parent, class_name: "Location", optional: true
  has_many :children, -> { order(:position, :name) }, class_name: "Location", foreign_key: :parent_id,
    inverse_of: :parent, dependent: :restrict_with_error
  has_many :stock_levels, dependent: :restrict_with_error
  has_many :stock_movements, dependent: :restrict_with_error
  has_many :item_units, dependent: :restrict_with_error
  has_many :home_items, class_name: "Item", foreign_key: :home_location_id, inverse_of: :home_location, dependent: :nullify

  attribute :location_type_id, default: -> { LocationType.default_for_new_places&.id }

  validates :name, presence: true
  validate :parent_is_not_inside_self
  validate :machine_placement
  validate :code_unique_in_top_level_place
  validate :empty_before_deactivating

  before_validation :take_parent_team
  before_validation { self.code = code.to_s.strip.presence }

  scope :active, -> { where(active: true) }
  scope :top_level, -> { where(parent_id: nil) }
  scope :ordered, -> { order(:position, :name) }
  # Places that keep counted stock, and places parts get installed on.
  scope :storage, -> { where(location_type_id: LocationType.for_stock.select(:id)) }
  scope :machine, -> { where(location_type_id: LocationType.for_installed_parts.select(:id)) }

  def self.ransackable_attributes(auth_object = nil)
    %w[name code location_type_id team_id parent_id active]
  end

  def identifier_icon
    machine? ? Inventory::MACHINE_ICON : "box-archive"
  end

  # Keeps counted stock (and spare units).
  def storage?
    location_type&.holds_stock? || false
  end

  # Parts get installed on it.
  def machine?
    location_type&.holds_installed_parts? || false
  end

  # Parts can be installed on it now: its type takes them and isn't retired.
  def takes_installs?
    machine? && location_type.active?
  end

  # "a robot": its type's name, for messages about this place.
  def type_word(article: false)
    location_type&.word(article: article) || "place"
  end

  def ancestors
    parent ? parent.ancestors + [ parent ] : []
  end

  def path
    ancestors + [ self ]
  end

  # "Build shop › Cabinet A › Bin 3".
  def full_name
    path.map(&:name).join(" › ")
  end

  def top_level
    parent ? parent.top_level : self
  end

  # This location and every location inside it.
  def subtree_ids
    [ id ] + Location.where(parent_id: id).flat_map(&:subtree_ids)
  end

  # Something recorded below zero here: show "Needs a count".
  def needs_count?
    stock_levels.where("quantity < 0").exists?
  end

  # Any stock or units here (not counting places inside it).
  def holds_anything?
    stock_levels.where.not(quantity: 0).exists? || item_units.where(active: true).exists?
  end

  # When someone last counted anything here, or nil.
  def last_counted_at
    stock_movements.counted.where(reverses_id: nil).maximum(:created_at)
  end

  # Units here that aren't inside another unit: the top of each assembly.
  def mounted_units
    item_units.where(installed_in_id: nil)
  end

  private

  def take_parent_team
    self.team_id ||= parent&.team_id
  end

  def parent_is_not_inside_self
    return if parent_id.nil? || new_record?

    seen = Set[id]
    current = parent_id
    while current
      return errors.add(:parent, "can't be this place or one inside it") if seen.include?(current)

      seen << current
      current = Location.where(id: current).pick(:parent_id)
    end
  end

  def machine_placement
    return unless location_type

    if will_save_change_to_location_type_id? && !location_type.active?
      errors.add(:location_type, "#{location_type.name} is retired: pick another type")
    end
    if machine? && parent&.machine?
      errors.add(:parent, "must be a place parts aren't installed on, or blank, for #{type_word(article: true)}")
    end
    if persisted? && will_save_change_to_location_type_id? && !storage? && stock_levels.where.not(quantity: 0).exists?
      errors.add(:location_type, "can't be #{type_word(article: true)} while counted stock is kept here: move or remove it first")
    end
  end

  def code_unique_in_top_level_place
    return if code.blank?

    top = parent ? parent.top_level : self
    ids = top.persisted? ? top.subtree_ids : []
    clash = Location.where(id: ids).where.not(id: id).where("LOWER(code) = ?", code.downcase).exists?
    errors.add(:code, "is already used in #{top.name}") if clash
  end

  def empty_before_deactivating
    return unless persisted? && will_save_change_to_active? && !active?

    errors.add(:active, "can't be turned off while something is kept here: move or remove it first") if holds_anything?
  end
end
