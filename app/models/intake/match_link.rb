# A manager's answer to "Might be the same person as <name>. Link or keep
# separate." on a person intake created.
#
# Link attaches what intake made for this registration to the matched
# person: the applications, the entry and household rows, the guardian ties
# and the login (the matched person has none: matches are only people with
# no login). It is not a merge: it is refused when the intake-made person
# has anything else (memberships, badges, check-ins, punches, tokens, other
# applications), and the person intake made, then empty, is deleted.
#
# Keep separate clears the flag and remembers the answer.
class Intake::MatchLink
  class Refused < StandardError; end

  attr_reader :member, :person, :match, :registration

  def initialize(member)
    @member = member
    @person = member.person
    @match = member.possible_match
    @registration = member.entry.registration
  end

  def keep_separate!
    member.update!(facts: member.facts.except("possible_match_id").merge("kept_separate_from_id" => match&.id))
  end

  def link!
    raise Refused, "There's no possible match to link." unless person && match
    raise Refused, "#{match.display_name} has a login now. Ask an admin to sort it out." if match.user && person.user
    raise Refused, "#{person.display_name} has other records, so they can't be linked here. Keep them separate for now." unless only_intake_records?

    Person.transaction do
      move_applications
      Intake::Entry.where(person: person).find_each { |entry| entry.update!(person: match) }
      Intake::HouseholdMember.where(person: person).find_each { |row| row.update!(person: match) }
      move_relationships
      move_details
      move_login
      member.update!(facts: member.facts.except("possible_match_id").merge("linked_from_id" => person.id))
      person.reload.destroy!
    end
    match
  end

  private

  def only_intake_records?
    person.memberships.none? && person.badge_assignments.none? && person.checkins.none? &&
      person.time_clock_punches.none? && person.tokens.none? &&
      person.membership_applications.where.not(registration_id: registration.id).none?
  end

  def move_applications
    person.membership_applications.where(registration: registration).find_each do |application|
      if match.membership_applications.exists?(team_id: application.team_id)
        application.destroy!
      else
        application.update!(person: match)
      end
    end
  end

  # Guardian ties intake made. The type's "added by" rule is about members
  # adding ties by hand, so it isn't run (as when intake made them).
  def move_relationships
    person.relationships.find_each do |relationship|
      side = relationship.parent_id == person.id ? :parent : :child
      other = side == :parent ? relationship.child : relationship.parent
      if other == match || Relationship.exists?(relationship_type_id: relationship.relationship_type_id, side => match, (side == :parent ? :child : :parent) => other)
        relationship.destroy!
      else
        relationship.public_send(:"#{side}=", match)
        relationship.save!(validate: false)
      end
    end
  end

  # A birthday or field answer the matched person doesn't have yet.
  def move_details
    match.update!(birthday: person.birthday) if match.birthday.nil? && person.birthday
    have = match.person_field_values.pluck(:person_field_id)
    person.person_field_values.where.not(person_field_id: have).find_each { |row| row.update!(person: match) }
  end

  def move_login
    user = person.user
    return unless user
    person.update!(user: nil)
    match.update!(user: user)
  end
end
