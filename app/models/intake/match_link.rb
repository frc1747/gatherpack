# A manager's answer to "Might be the same person as <name>. Link or keep
# separate." on a person intake created.
#
# Link attaches this registration's applications and the sign-up (entry
# and household row) to the matched person. It never moves a login or a
# guardian tie, so it can't hand one person's account or family to
# another: the new record keeps its login and ties. When the new person had
# guardians, each becomes a guardian request on the matched person that a
# manager must confirm (nothing is emailed to them). Merging the two
# records is left to person merge.
#
# Only for a linker who can manage the matched person, and never onto
# someone who manages a team or holds a badge the linker couldn't give.
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

  # What Link would do, for its confirmation.
  def description
    applications = applications_to_move.map { |application| application.team.name }
    text = "Moves #{person.first_name}'s sign-up"
    text += " and #{"application".pluralize(applications.size)} to #{applications.to_sentence}" if applications.any?
    text += " to #{match.display_name}. #{person.first_name}'s login and family links stay where they are"
    text += guardians.any? ? "; a manager confirms #{guardians.map(&:display_name).to_sentence} as #{match.first_name}'s guardian." : "."
    text
  end

  def link!(by:)
    raise Refused, "There's no possible match to link." unless person && match
    refuse_unless_allowed(by)

    Person.transaction do
      applications_to_move.each do |application|
        if match.membership_applications.exists?(team_id: application.team_id)
          application.destroy!
        else
          application.update!(person: match)
        end
      end
      member.entry.update!(person: match) if member.entry.person == person
      guardians.each { |guardian| request_guardian(guardian) }
      member.update!(person: match, facts: member.facts.except("possible_match_id").merge("linked_from_id" => person.id))
    end
    match
  end

  private

  def refuse_unless_allowed(by)
    raise Refused, "You can only link to someone you manage." unless by&.can_manage(match)
    raise Refused, "#{match.display_name} manages a team, so they can't be linked here." if match.memberships.where(manager: true).exists?
    if match.badges.any? { |badge| !BadgePolicy.new(by.user, badge).update? }
      raise Refused, "#{match.display_name} holds a badge you can't give, so they can't be linked here."
    end
  end

  def applications_to_move
    person.membership_applications.pending.where(registration: registration).includes(:team).to_a
  end

  def guardians
    @guardians ||= person.guardians.to_a
  end

  # A guardian request a manager confirms on the guardian tools; it has no
  # link, so the would-be guardian can't confirm it themselves.
  def request_guardian(guardian)
    return if match.guardians.include?(guardian)
    member.entry.household_members.create!(role: :guardian, facts: {
      "ward_id" => match.id, "first_name" => guardian.first_name, "last_name" => guardian.last_name,
      "person_id" => guardian.id, "manager_confirms" => true
    })
  end
end
