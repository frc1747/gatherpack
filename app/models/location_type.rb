# A type of place (inventory spec §3.15), managed on Setup: Storage, Machine,
# or whatever a group calls them. Code reads the flags, never the name:
# holds_stock places keep counted stock and spare units; places of a type
# that holds_installed_parts have tracked parts installed on them, each with
# its own page. While such a type is retired its places keep it, but no
# part can be installed on them.
class LocationType < ApplicationRecord
  include ManagedList
  has_neat_id :plty
  managed_list uses: { locations: :location_type_id }

  has_many :locations, dependent: :restrict_with_error

  scope :for_installed_parts, -> { where(holds_installed_parts: true) }
  scope :for_stock, -> { where(holds_stock: true) }

  # The active types parts get installed on, in order: one menu entry and
  # page each.
  def self.installable
    active.for_installed_parts.ordered
  end

  # The type a new place starts with: the first active one that holds stock.
  def self.default_for_new_places
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
end
