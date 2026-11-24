# A person whose only records are denied registration applications (and the
# entry rows that made them) can be deleted with their login. Anything else
# (a membership, a relationship, a badge, check-ins, punches, form answers,
# another application) keeps them.
class Intake::SpamPerson
  attr_reader :person

  def initialize(person)
    @person = person
  end

  def deletable?
    applications = person.membership_applications
    applications.exists? && applications.where.not(status: :denied).none? && applications.where(registration_id: nil).none? &&
      person.memberships.none? && person.relationships.none? && person.badge_assignments.none? &&
      person.checkins.none? && person.time_clock_punches.none? && !answered_forms?
  end

  # What deleting removes, for the confirmation screen.
  def summary
    lines = [ "#{person.display_name}'s profile" ]
    lines << "their login (#{person.user.email})" if person.user
    count = person.membership_applications.count
    lines << "#{count} denied #{"application".pluralize(count)}"
    lines
  end

  def destroy!
    Person.transaction do
      user = person.user
      person.destroy!
      user&.destroy!
    end
  end

  private

  def answered_forms?
    defined?(FormResponse) && FormResponse.column_names.include?("person_id") && FormResponse.where(person_id: person.id).exists?
  end
end
