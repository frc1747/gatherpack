# Members: create?, update? and destroy? (cancel) for their own sign-ups and
# those of people they can sign up. Organizers: place?, mark? (fulfilled or
# no-show), move? and override? (place against a rule). No one can mark,
# move or override for themselves or a relative (SignupSheet#self_or_relative?);
# #self_approval_reason says why.
class SignupPolicy < ApplicationPolicy
  def create?
    sheet.open? && sheet.takers_for(person).exists?(id: record.person_id || person&.id)
  end

  def update?
    sheet.open? && mine? && record.cancellable_by_member?
  end

  def destroy?
    update?
  end

  # Add, edit or cancel any sign-up from the roster.
  def place?
    organizer? && !sheet.archived?
  end

  def mark?
    place? && !self_or_relative?
  end

  def move?
    place? && !self_or_relative?
  end

  # Whether a sign-up can be moved to this person.
  def move_to?(target)
    move? && !sheet.self_or_relative?(person, target)
  end

  def override?
    place? && !self_or_relative?
  end

  def self_approval_reason
    SignupSheet::SELF_APPROVAL_REASON if self_or_relative?
  end

  private

  def sheet
    record.signup_sheet
  end

  def organizer?
    sheet.organizer?(person)
  end

  def mine?
    return false if person.nil?
    return true if [ record.person_id, record.signed_up_by_id, record.on_behalf_of_id ].include?(person.id)

    sheet.takers_for(person).exists?(id: record.person_id)
  end

  def self_or_relative?
    [ record.person, record.on_behalf_of ].compact.any? { |someone| sheet.self_or_relative?(person, someone) }
  end
end
