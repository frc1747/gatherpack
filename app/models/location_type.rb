# A type of place (inventory spec §3.15), managed on Setup: Storage, Machine,
# or whatever a group calls them. Code reads the flags, never the name:
# holds_stock places keep counted stock and spare units; places of a type
# that holds_installed_parts have tracked parts installed on them, each with
# its own page. A type is one or the other (or neither, for a place that
# only holds other places), and a type in use can't drop a flag its places
# rely on. While such a type is retired its places keep it, but no part can
# be installed on them.
class LocationType < ApplicationRecord
  include ManagedList
  has_neat_id :plty
  managed_list uses: { locations: :location_type_id }

  has_many :locations, dependent: :restrict_with_error

  validate :one_purpose
  validate :flags_fit_places, if: :persisted?

  scope :for_installed_parts, -> { where(holds_installed_parts: true) }
  scope :for_stock, -> { where(holds_stock: true) }

  # The active types parts get installed on, in order: one menu entry and
  # page each.
  def self.installable
    Inventory::Lists.seed!(LocationType)
    active.for_installed_parts.ordered
  end

  # The type a new place starts with: the first active one that holds stock.
  def self.default_for_new_places
    Inventory::Lists.seed!(LocationType)
    active.for_stock.ordered.first || active.ordered.first
  end

  # "a robot or a practice base": the active types parts go on, for a
  # message that can't name one place.
  def self.installable_words(article: true)
    words = installable.map { |type| type.word(article: article) }
    words.any? ? words.to_sentence(two_words_connector: " or ", last_word_connector: " or ") : "a place parts get installed on"
  end

  # The name mid-sentence: "robot", "a robot", "an arm" ("CNC mill" keeps
  # its capitals).
  def word(article: false, count: 1)
    text = count == 1 ? name : plural_name
    text = text.match?(/\A[[:upper:]]{2}/) ? text : text[0].downcase + text[1..]
    return text unless article && count == 1

    "#{text.match?(/\A[aeiou]/i) ? "an" : "a"} #{text}"
  end

  # Only into a type that does the same, so no place changes what it does.
  def merge_into!(other)
    if other.is_a?(LocationType) && [ other.holds_stock, other.holds_installed_parts ] != [ holds_stock, holds_installed_parts ]
      errors.add(:base, "#{name} can only be merged into a type that keeps stock and takes installed parts the same way")
      raise ActiveRecord::RecordInvalid, self
    end

    super
  end

  private

  def one_purpose
    return unless holds_stock? && holds_installed_parts?

    errors.add(:base, "A type either keeps stock or has parts installed on it, not both")
  end

  # Unticking Keeps stock would strand the counted stock in its places, and
  # ticking Parts get installed on it would put that stock on a machine;
  # unticking Parts get installed on it would turn installed parts into
  # spares.
  def flags_fit_places
    places = Location.where(location_type_id: id)
    stocked = StockLevel.where(location_id: places.select(:id)).where.not(quantity: 0).exists?
    if stocked && ((will_save_change_to_holds_stock? && !holds_stock?) ||
        (will_save_change_to_holds_installed_parts? && holds_installed_parts?))
      errors.add(:base, "Counted stock is kept in #{plural_name.downcase}: move or remove it first")
    end
    if will_save_change_to_holds_installed_parts? && !holds_installed_parts? &&
        ItemUnit.active.where(location_id: places.select(:id)).exists?
      errors.add(:base, "Parts are installed on #{plural_name.downcase}: take them off first")
    end
  end
end
