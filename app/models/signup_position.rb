# Something a sheet asks for: people to work ("Cashier") or items to bring
# ("Main dish", counted in its unit). The capacity is the default for each
# of its slots: places for people, a quantity for items. No capacity takes
# any number.
class SignupPosition < ApplicationRecord
  has_neat_id :supo
  include CanBeHooked
  include Signups::SheetChanges
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :signup_sheet

  # Must run before the dependent destroys below.
  before_destroy :check_no_signups, prepend: true

  has_many :signup_position_rules, -> { order(:created_at) }, dependent: :destroy, inverse_of: :signup_position
  has_many :signup_slots, dependent: :destroy
  has_many :signups, through: :signup_slots

  enum :kind, { people: 0, items: 1 }, validate: true

  validates :name, presence: true
  validates :capacity, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :question, presence: { message: "is needed to make an answer required" }, if: :question_required?

  before_create :place_last
  after_create :add_slots

  def identifier_name
    name
  end

  # Why this person can't take this position at this event, one reason per
  # failing rule. Empty when they can.
  def eligibility_failures(person, event)
    signup_position_rules.filter_map { |rule| rule.check(person, event) }
  end

  def eligible?(person, event)
    eligibility_failures(person, event).empty?
  end

  def add_slots_for!(event_ids)
    existing = signup_slots.where(event_id: event_ids).pluck(:event_id)
    (event_ids - existing).each { |event_id| signup_slots.create!(event_id: event_id) }
  end

  # "pizzas" for item positions with a unit; "places" for people.
  def unit_label
    people? ? "places" : unit.presence || "items"
  end


  # For Signups::SheetChanges.
  def changed_signup_sheet_id
    signup_sheet_id
  end
  private

  def place_last
    self.position = (signup_sheet.signup_positions.maximum(:position) || -1) + 1 if position.to_i.zero?
  end

  def add_slots
    add_slots_for!(signup_sheet.signup_sheet_events.pluck(:event_id))
  end

  def check_no_signups
    return unless signups.live.exists?

    errors.add(:base, "#{name} has sign-ups, so it can't be deleted")
    throw :abort
  end
end
