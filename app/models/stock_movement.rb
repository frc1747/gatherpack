# One change to the quantity of an item at a location (inventory spec
# §3.1–3.3). Stock is the sum of movements; StockLevel caches it per
# location. Movements are never edited or deleted, by anyone: an undo is a
# reversing movement (reverses_id), and the original stays.
#
# StockMovement.record! is the supported way to change stock, for pages and
# for other features alike.
class StockMovement < ApplicationRecord
  has_neat_id :smv
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }, on: %i[create]

  KINDS = Inventory::Config::KINDS
  # Kinds recorded as a positive number that takes stock out, or puts it in.
  OUT_KINDS = %w[used removed].freeze
  IN_KINDS = %w[received added].freeze
  NEEDS_REASON = %w[added removed].freeze

  belongs_to :item
  belongs_to :location
  belongs_to :person, optional: true
  belongs_to :recorded_by, class_name: "Person", optional: true
  belongs_to :reverses, class_name: "StockMovement", optional: true
  has_one :reversal, class_name: "StockMovement", foreign_key: :reverses_id, inverse_of: :reverses, dependent: nil

  enum :kind, KINDS.index_by(&:itself), validate: true

  validates :quantity, numericality: { only_integer: true }

  # What record! worked out for the notification and hooks, sent once the
  # transaction commits, and the location's level just after this row.
  attr_accessor :announcement, :stock_after

  after_create_commit :announce

  before_destroy { raise ActiveRecord::ReadOnlyRecord, "Stock changes can't be deleted" }

  scope :newest_first, -> { order(created_at: :desc) }
  scope :undone, -> { where(id: StockMovement.where.not(reverses_id: nil).select(:reverses_id)) }

  def self.ransackable_attributes(auth_object = nil)
    %w[kind item_id location_id person_id recorded_by_id created_at]
  end

  def readonly?
    persisted? || super
  end

  # delete skips callbacks and the readonly check, so refuse it here too.
  def delete
    raise ActiveRecord::ReadOnlyRecord, "Stock changes can't be deleted"
  end

  def identifier_name
    "#{kind.humanize} #{quantity.abs} #{item&.name}"
  end

  def identifier_icon
    "right-left"
  end

  # Records a movement and returns it (for a move, the row out of the
  # first location; #move_rows has both). quantity is a positive number
  # for every kind but counted, where it's the number seen; moved takes all
  # of the stock when it's blank, and used takes 1. location defaults to
  # the item's default location for used and received.
  #
  # Runs the same check as the pages unless authorized_by: is given (the
  # caller's own policy decision). Raises Inventory::Refused with a message
  # fit to show.
  def self.record!(kind:, item:, person:, location: nil, quantity: nil, reason: nil, note: nil, recorded_by: nil,
    to_location: nil, authorized_by: nil)
    kind = kind.to_s
    raise Inventory::Refused, "Unknown kind of change: #{kind}" unless KINDS.include?(kind)

    location ||= item.default_location if kind.in?(%w[used received])
    check_recordable!(kind, item, location, to_location)
    actor = recorded_by || person
    unless authorized_by || Inventory::Access.for(actor).may_record?(kind, item, location, to_location)
      raise Inventory::Refused, "You can't record #{kind.humanize.downcase} for #{item.name} here"
    end

    reason = reason.to_s.strip.presence
    if kind.in?(NEEDS_REASON) || (kind == "used" && Inventory::Config.used_needs_reason?)
      raise Inventory::Refused, (kind == "used" ? "Say what it was for" : "Give a reason") if reason.nil?
    end

    count = whole_number(quantity)
    raise Inventory::Refused, "The quantity must be a whole number" if count == :invalid
    attributes = { kind: kind, item: item, person: person, recorded_by: (recorded_by if recorded_by != person),
      reason: reason, note: note.to_s.strip.presence }

    apply!(item) do
      case kind
      when "counted"
        raise Inventory::Refused, "Type the number you see" if count.nil? || count.negative?

        level = StockLevel.locked_for(item, location)
        [ write_row!(**attributes, location: location, quantity: count - level.quantity, counted_quantity: count, level: level) ]
      when "moved"
        move_rows!(attributes, item, location, to_location, count)
      else
        count = 1 if count.nil? && kind == "used"
        raise Inventory::Refused, "The quantity must be a whole number above zero" if count.nil? || count <= 0

        [ write_row!(**attributes, location: location, quantity: kind.in?(OUT_KINDS) ? -count : count) ]
      end
    end.first
  end

  # Inserts one row and moves the location's level by its quantity, under
  # the level's row lock. Low-level: no permission checks, no notification
  # or crossing hooks (record! and undo! add those).
  def self.write_row!(kind:, item:, location:, quantity:, level: nil, **attributes)
    level ||= StockLevel.locked_for(item, location)
    level.update!(quantity: level.quantity + quantity)
    movement = create!(kind: kind, item: item, location: location, quantity: quantity, **attributes)
    movement.stock_after = level.quantity
    movement
  end

  def recorder_id
    recorded_by_id || person_id
  end

  # Asks the database each time, so a check inside undo!'s lock sees a
  # reversal another request has just written.
  def undone?
    StockMovement.where(reverses_id: move_rows.map(&:id)).exists?
  end

  def reversal?
    reverses_id.present?
  end

  # Both rows of a move, out then in; just this row otherwise.
  def move_rows
    return [ self ] if move_group_id.nil?

    StockMovement.where(move_group_id: move_group_id).order(:quantity).to_a
  end

  # The recorder within inventory_undo_minutes, and managers of the item's
  # team at any time. A reversal and an undone movement can't be undone.
  def undoable_by?(person, at: Time.current)
    return false if person.nil? || reversal? || undone?

    access = Inventory::Access.for(person)
    return true if access.manages?(item.team_id)

    recorder_id == person.id && access.sees?(item) && created_at > at - Inventory::Config.undo_minutes.minutes
  end

  # Writes the reversing movement(s): the same kind, the opposite quantity,
  # reverses_id set. Returns the reversal of this row.
  def undo!(by:, recorded_by: nil, note: nil)
    actor = recorded_by || by
    raise Inventory::Refused, "This change can't be undone" unless undoable_by?(actor)

    originals = move_rows
    group = move_group_id && SecureRandom.uuid
    reversals = self.class.apply!(item) do
      raise Inventory::Refused, "This change has already been undone" if undone?

      originals.map do |original|
        self.class.write_row!(kind: kind, item: item, location: original.location, quantity: -original.quantity,
          person: by, recorded_by: (recorded_by if recorded_by != by), reverses: original, move_group_id: group,
          reason: original.reason, note: note.to_s.strip.presence || "Undo")
      end
    end
    reversals.find { |row| row.reverses_id == id }
  end

  # The crossing work shared by record! and undo!: locks the item (so
  # totals before and after are this change's alone), runs the block that
  # writes rows, and leaves each row what to announce after commit.
  def self.apply!(item, &block)
    rows = nil
    announce = lambda do |crossings, after|
      rows.each_with_index do |row, index|
        row.announcement = { stock_after: row.stock_after, total_after: after, went_low: crossings.include?(:running_low),
          crossings: index == rows.size - 1 ? crossings : [] }
      end
    end
    Inventory::Stock.with_crossings(item, announce: announce) { rows = block.call }
  end

  def self.check_recordable!(kind, item, location, to_location)
    raise Inventory::Refused, "Pick a place" if location.nil?
    raise Inventory::Refused, "#{item.name} is tracked: change its units instead" if item.tracked?
    raise Inventory::Refused, "#{item.name} isn't active" unless item.active?
    raise Inventory::Refused, "#{location.name} isn't active" unless location.active?
    if (place = [ location, to_location ].compact.find { |candidate| !candidate.storage? })
      raise Inventory::Refused, "#{place.name} is #{place.type_word(article: true)}, which holds no stock"
    end
    return unless kind == "moved"

    raise Inventory::Refused, "Pick where it's going" if to_location.nil?
    raise Inventory::Refused, "Pick a different place to move it to" if to_location.id == location.id
    raise Inventory::Refused, "#{to_location.name} isn't active" unless to_location.active?
  end

  def self.move_rows!(attributes, item, from, to, count)
    group = SecureRandom.uuid
    # Lock both levels in a fixed order, so two moves can't wait on each other.
    levels = [ from, to ].sort_by(&:id).to_h { |place| [ place.id, StockLevel.locked_for(item, place) ] }
    count = [ levels[from.id].quantity, 0 ].max if count.nil?
    raise Inventory::Refused, "There's nothing here to move" if count <= 0

    [ write_row!(**attributes, location: from, quantity: -count, move_group_id: group, level: levels[from.id]),
      write_row!(**attributes, location: to, quantity: count, move_group_id: group, level: levels[to.id]) ]
  end

  # nil when blank (the kind's default applies), :invalid when it isn't a
  # whole number ("2.5", "3x", 2.5).
  def self.whole_number(value)
    return nil if value.nil? || value.to_s.strip.empty?
    return value if value.is_a?(Integer)
    return :invalid unless value.is_a?(String)

    Integer(value.strip, 10, exception: false) || :invalid
  end

  private_class_method :check_recordable!, :move_rows!, :whole_number

  private

  def announce
    return if announcement.nil?

    Inventory.movement_recorded(self, stock_after: announcement[:stock_after], total_after: announcement[:total_after],
      went_low: announcement[:went_low])
    Inventory.run_hooks(Inventory::COUNT_DIFFERS_EVENT, self) if counted? && !quantity.zero? && !reversal?
    InventoryNotices.new.count_differs(self) if counted?
    Inventory::Stock.announce_crossings(item, announcement[:crossings])
  end
end
