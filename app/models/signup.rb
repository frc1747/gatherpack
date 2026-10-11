# A person in a slot. A people sign-up uses 1 + extra_people places; an item
# sign-up uses its quantity. person takes the place (or brings the items),
# signed_up_by made the sign-up, and on_behalf_of is whose sign-up it counts
# as (usually the person; see SignupSheet#on_behalf_of_choices_for).
#
# Make and change sign-ups through Signup.place! and #change!, which check
# the slot's capacity inside a row lock on the slot, so two people can't take
# the last place at once.
class Signup < ApplicationRecord
  has_neat_id :sup
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :signup_slot
  belongs_to :person
  belongs_to :signed_up_by, class_name: "Person", optional: true
  belongs_to :on_behalf_of, class_name: "Person", optional: true

  # For items, fulfilled reads "Brought" and no_show "Not brought".
  enum :status, { active: 0, cancelled: 1, fulfilled: 2, no_show: 3 }, validate: true

  # Sign-ups that use up their slot's capacity.
  scope :counted, -> { where(status: %i[ active fulfilled ]) }
  # Sign-ups that still matter: everything but cancelled.
  scope :live, -> { where.not(status: :cancelled) }

  validates :extra_people, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :fits_position_kind, if: -> { new_record? || will_save_change_to_signup_slot_id? || will_save_change_to_quantity? || will_save_change_to_extra_people? }

  before_validation -> { self.on_behalf_of ||= person }
  after_update :run_status_hooks, if: :saved_change_to_status?

  delegate :signup_position, :signup_sheet, :event, to: :signup_slot

  CHANGEABLE = %i[ person on_behalf_of extra_people extra_names quantity answer note ].freeze

  def identifier_name
    "#{person&.display_name}: #{signup_slot&.identifier_name}"
  end

  # Places or units this sign-up uses of its slot.
  def usage
    signup_position.items? ? quantity.to_i : 1 + extra_people.to_i
  end

  # Signs a person up for a slot, or raises ActiveRecord::RecordInvalid with
  # the reasons it can't (the slot is full, a rule fails, ...). Organizers
  # may place anyone on a sheet that isn't archived, and with override_rules
  # against a failing rule, unless the person is themselves or a relative.
  def self.place!(slot:, person:, signed_up_by:, on_behalf_of: nil, extra_people: 0, extra_names: nil, quantity: nil, answer: nil, note: nil, override_rules: false)
    signup = new(signup_slot: slot, person: person, signed_up_by: signed_up_by, on_behalf_of: on_behalf_of || person,
      extra_people: extra_people.presence || 0, extra_names: extra_names, quantity: quantity.presence, answer: answer, note: note)

    transaction do
      slot.lock!
      signup.check_placement!(by: signed_up_by, override_rules: override_rules)
      signup.save!
    end
    signup
  end

  # Changes this sign-up (a different slot is a move), with the same checks
  # as Signup.place!. Capacity leaves out what this sign-up already uses.
  def change!(by:, slot: signup_slot, override_rules: false, **attributes)
    unknown = attributes.keys - CHANGEABLE
    raise ArgumentError, "can't change #{unknown.to_sentence}" if unknown.any?

    transaction do
      [ signup_slot, slot ].uniq.sort_by(&:id).each(&:lock!)
      self.signup_slot = slot
      assign_attributes(attributes)
      self.on_behalf_of ||= person
      self.extra_people = 0 if extra_people.blank?
      self.quantity = quantity.presence
      check_placement!(by: by, override_rules: override_rules)
      save!
    end
    true
  end

  def cancel!
    update!(status: :cancelled)
  end

  # Members can cancel until cancel_cutoff_hours before the event starts.
  def cancellable_by_member?(now = Time.current)
    active? && now < event.start_time - signup_sheet.cancel_cutoff_hours.hours
  end

  # Adds the reasons this sign-up can't be placed (or changed) by this
  # person, and raises ActiveRecord::RecordInvalid if there are any.
  def check_placement!(by:, override_rules: false)
    errors.clear
    placement_problems(by, override_rules).each { |problem| errors.add(:base, problem) }
    raise ActiveRecord::RecordInvalid, self if errors.any?
  end

  private

  def placement_problems(by, override_rules)
    sheet = signup_sheet
    slot = signup_slot
    organizer = sheet.organizer?(by)
    moved = new_record? || will_save_change_to_signup_slot_id? || will_save_change_to_person_id?

    return [ "This sign-up was cancelled" ] if cancelled?
    return [ "This sheet is archived" ] if sheet.archived?
    return [ "This sheet isn't open for sign-ups" ] unless sheet.open? || organizer
    return [ "This slot is turned off" ] if slot.disabled? && moved
    return [ "A sign-up can only move within its sheet" ] if persisted? && will_save_change_to_signup_slot_id? && SignupSlot.find(signup_slot_id_was).signup_sheet != sheet

    problems = []
    unless organizer
      problems << "You can't sign up #{person.display_name} on this sheet" if moved && !sheet.takers_for(by).exists?(id: person.id)
      if new_record? || will_save_change_to_on_behalf_of_id?
        problems << "You can't sign up on behalf of #{on_behalf_of&.display_name}" unless sheet.on_behalf_of_choices_for(by, person).exists?(id: on_behalf_of_id)
      end
    end
    problems.concat(rule_problems(by, organizer, override_rules)) if moved
    problems << "Answer \"#{signup_position.question}\"" if signup_position.question_required? && answer.blank?
    problems << capacity_problem(moved)
    problems.compact
  end

  def rule_problems(by, organizer, override_rules)
    failures = signup_position.eligibility_failures(person, event)
    return failures unless override_rules && failures.any?
    return [ "Only organizers can place people against a rule" ] unless organizer
    return [ "Another organizer needs to place your own family against a rule" ] if signup_sheet.self_or_relative?(by, person)

    []
  end

  # Checked when the sign-up is new, moves, or grows, so an edit to a slot
  # that was over its cap (an organizer lowered it) can still change a note.
  def capacity_problem(moved)
    remaining = signup_slot.remaining(excluding: self)
    return if remaining.nil? || usage <= remaining
    return unless moved || usage > previous_usage

    if remaining.zero?
      "This slot is full"
    elsif signup_position.items?
      "Only #{remaining} #{remaining == 1 ? signup_position.unit_label.singularize : signup_position.unit_label} still needed"
    else
      "Only #{remaining} #{remaining == 1 ? "place" : "places"} left"
    end
  end

  def previous_usage
    signup_position.items? ? quantity_was.to_i : 1 + extra_people_was.to_i
  end

  def fits_position_kind
    return unless signup_slot

    if signup_position.items?
      errors.add(:quantity, "is needed") if quantity.nil?
      errors.add(:extra_people, "are only for people positions") if extra_people.to_i.positive?
    elsif !quantity.nil?
      errors.add(:quantity, "is only for item positions")
    end
  end

  def run_status_hooks
    event = { "fulfilled" => "signups - fulfilled", "cancelled" => "signups - cancelled" }[status]
    Hook.where(event: event).each { |hook| hook.run(self) } if event
  end
end
