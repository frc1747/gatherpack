# A person's saved default for one housekeeping list (H2): the view it opens
# on and the "ended before" filter. Without a row the default is "current":
# the not-archived ones, any end date.
class HousekeepingPreference < ApplicationRecord
  has_neat_id :hkpr

  VIEWS = %w[current archived].freeze

  belongs_to :person

  validates :list_key, presence: true, uniqueness: { scope: :person_id }
  validates :view, inclusion: { in: VIEWS }

  # The saved default, or an unsaved "current" one.
  def self.for(person, list_key)
    find_by(person: person, list_key: list_key.to_s) || new(person: person, list_key: list_key.to_s, view: "current")
  end

  def self.save_for!(person, list_key, view:, older:)
    preference = find_or_initialize_by(person: person, list_key: list_key.to_s)
    preference.update!(view: VIEWS.include?(view) ? view : "current", older: older)
    preference
  end

  def archived?
    view == "archived"
  end

  def older_than
    Checklists::RelativeDate.from_config(older)
  end
end
