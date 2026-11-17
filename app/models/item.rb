# A kind of thing kept: "M4 × 12 socket head screw", not one screw
# (inventory spec §3.1). Counted in one stock unit (StockUnit, a list
# managed on Setup), in whole numbers.
# Its stock is the sum of its movements (StockMovement), cached per
# location in StockLevel. A tracked item (§3.15) has no movements of its
# own: each piece is an ItemUnit, and its stock is the units available.
class Item < ApplicationRecord
  has_neat_id :itm
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :team
  belongs_to :home_location, class_name: "Location", optional: true, inverse_of: :home_items
  belongs_to :stock_unit
  # The readings a tracked item's checks ask for, in order.
  has_many :item_reading_types, -> { order(:position) }, inverse_of: :item, dependent: :delete_all, autosave: true
  has_many :reading_types, -> { order("item_reading_types.position") }, through: :item_reading_types
  has_many :item_sources, -> { ordered }, inverse_of: :item, dependent: :destroy
  has_many :stock_movements, dependent: :restrict_with_error
  has_many :stock_levels, dependent: :delete_all
  has_many :item_units, dependent: :restrict_with_error
  has_one_attached :photo

  validates :name, presence: true
  validates :reorder_point, :reorder_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :untracking_without_units
  validate :tracking_through_start_tracking
  validate :home_location_is_storage

  attribute :stock_unit_id, default: -> { StockUnit.default_unit&.id }

  scope :active, -> { where(active: true) }
  scope :tracked, -> { where(tracked: true) }

  def self.ransackable_attributes(auth_object = nil)
    %w[name category manufacturer manufacturer_part_number team_id active tracked]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end

  # The stock unit's name, for other features and tools that show it as text.
  def unit
    stock_unit&.name
  end

  # Sets the stock unit by name or plural, adding a unit to the list when
  # none matches. Kept for features that set the unit as text; blank keeps
  # the current one.
  def unit=(text)
    return if text.to_s.strip.empty?

    self.stock_unit = StockUnit.named(text) || StockUnit.new(name: text.to_s.strip)
  end

  def identifier_icon
    tracked? ? "microchip" : "box"
  end

  # Active items the viewer (a Person) sees whose name, part numbers,
  # category or a source's part number contain the query.
  def self.search(query, viewer:)
    access = Inventory::Access.for(viewer)
    scope = active
    scope = scope.where(team_id: access.visible_team_ids.to_a) unless access.admin?
    words = query.to_s.strip
    return scope.order(:name) if words.empty?

    pattern = "%#{sanitize_sql_like(words)}%"
    by_source = ItemSource.where("vendor_part_number ILIKE :p", p: pattern).select(:item_id)
    scope.where("items.name ILIKE :p OR items.manufacturer_part_number ILIKE :p OR items.category ILIKE :p", p: pattern)
      .or(scope.where(id: by_source))
      .order(:name)
  end

  # Categories in use, for suggestions.
  def self.categories
    where.not(category: [ nil, "" ]).distinct.order(:category).pluck(:category)
  end

  def preferred_source
    item_sources.find(&:preferred?) || item_sources.first
  end

  # What another feature needs to describe this item, as plain keys.
  # Inventory doesn't know what the other feature does with them.
  def line_attributes
    source = preferred_source
    {
      name: name,
      description: description,
      manufacturer: manufacturer,
      manufacturer_part_number: manufacturer_part_number,
      unit: unit,
      vendor_name: source&.vendor_name,
      vendor_part_number: source&.vendor_part_number,
      url: source&.url.presence || url
    }
  end

  # The quantity at one location (a level can be negative: "Needs a count").
  def stock_at(location)
    stock_levels.find_by(location_id: location.id)&.quantity.to_i
  end

  # Total stock over active locations, negatives counted as zero; for a
  # tracked item, the units available.
  def total_stock
    Inventory::Stock.totals([ self ])[id].to_i
  end

  def on_order
    Inventory.extensions.on_order([ self ])[id].to_i
  end

  # Has a reorder point and total stock is at or below it.
  def low?(total = total_stock)
    !reorder_point.nil? && total <= reorder_point
  end

  def out_of_stock?(total = total_stock)
    total.zero?
  end

  # Total stock plus on order at or below the reorder point.
  def on_reorder_list?(total = total_stock, ordered = on_order)
    !reorder_point.nil? && total + ordered <= reorder_point
  end

  # How many to buy: the reorder quantity, or enough to get back to twice
  # the reorder point.
  def suggested_quantity(total = total_stock, ordered = on_order)
    return reorder_quantity if reorder_quantity.to_i.positive?

    [ (2 * reorder_point.to_i) - total - ordered, 1 ].max
  end

  # Where Used and Received start: the home location, or the only active
  # location with stock.
  def default_location
    return home_location if home_location&.active?

    places = stock_levels.where("stock_levels.quantity > 0").joins(:location).merge(Location.active).limit(2).map(&:location)
    places.one? ? places.first : nil
  end

  def last_counted_at
    stock_movements.counted.where(reverses_id: nil).maximum(:created_at)
  end

  # Sets the reading types checks ask for, in the order given. Types no
  # longer picked are unlinked; readings already saved keep their values.
  def reading_type_ids=(ids)
    ids = Array(ids).compact_blank.map(&:to_s).uniq
    links = item_reading_types.to_a
    links.reject { |link| ids.include?(link.reading_type_id) }.each(&:mark_for_destruction)
    ids.each_with_index do |id, position|
      link = links.find { |existing| existing.reading_type_id == id }
      link ? link.position = position : item_reading_types.build(reading_type_id: id, position: position)
    end
  end

  # Turns tracking on. Stock at each location becomes that many units
  # (codes to fill in later), and the stock is cleared with movements so
  # the history says where it went.
  def start_tracking!(by:, recorded_by: nil, authorized_by: nil)
    actor = recorded_by || by
    unless authorized_by || Inventory::Access.for(actor).manages?(team_id)
      raise Inventory::Refused, "Only an inventory manager can turn on tracking"
    end
    raise Inventory::Refused, "#{name} is already tracked" if tracked?

    transaction do
      lock!
      @starting_tracking = true
      update!(tracked: true)
      stock_levels.lock.where.not(quantity: 0).includes(:location).find_each do |level|
        if level.quantity.positive?
          level.quantity.times do
            ItemUnit.create_with_event!(item: self, location: level.location, person: by, recorded_by: recorded_by,
              note: "Was counted stock when tracking started")
          end
        end
        StockMovement.write_row!(kind: level.quantity.positive? ? "removed" : "added", item: self, location: level.location,
          quantity: -level.quantity, person: by, recorded_by: recorded_by, reason: "Now tracked as units")
      end
    end
    self
  ensure
    @starting_tracking = false
  end

  # Turns tracking off; refused while the item has units.
  def stop_tracking!(by:, authorized_by: nil)
    unless authorized_by || Inventory::Access.for(by).manages?(team_id)
      raise Inventory::Refused, "Only an inventory manager can turn off tracking"
    end
    raise Inventory::Refused, "Tracking can't be turned off while #{name} has units" if item_units.exists?

    update!(tracked: false)
    self
  end

  private

  def untracking_without_units
    return unless persisted? && will_save_change_to_tracked? && !tracked?

    errors.add(:tracked, "can't be turned off while the item has units") if item_units.exists?
  end

  # Turning tracking on for an existing item goes through start_tracking!,
  # which turns its stock into units, so no stock is lost.
  def tracking_through_start_tracking
    return unless persisted? && will_save_change_to_tracked? && tracked? && !@starting_tracking

    errors.add(:tracked, "is turned on with start_tracking!, which turns the item's stock into units")
  end

  def home_location_is_storage
    return if home_location.nil? || home_location.storage?

    errors.add(:home_location, "must be a place that keeps stock, not #{home_location.type_word(article: true)}")
  end
end
