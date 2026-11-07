# What happens once an entry's person is known: applications (or, for teams
# that need no approval, memberships) for the chosen teams, people added to
# the household, and guardian links. Shared by the self-service link and the
# kiosk; the source says which made the application.
class Intake::Enrollment
  class Refused < StandardError; end

  attr_reader :entry, :registration

  def initialize(entry)
    @entry = entry
    @registration = entry.registration
  end

  def source
    entry.source_kiosk? ? :kiosk : :link
  end

  # Applies a person to the given teams (the entry's choice by default),
  # limited to the registration's teams. Already a member, already waiting,
  # or decided before: nothing new. Returns the pending applications.
  def apply(person, teams = entry.teams)
    teams = registration.apply_teams.where(id: Array(teams).map { |team| team.try(:id) || team })
    teams.filter_map do |team|
      next if person.memberships.exists?(team: team)

      if team.requires_approval?
        # Upstream keeps one application per person and team, whatever its
        # status, so someone denied before isn't asked again here.
        existing = team.membership_applications.find_by(person: person)
        next existing if existing&.pending?
        next if existing
        MembershipApplication.create!(person: person, team: team, registration: registration, source: source)
      else
        Membership.create!(person: person, team: team, manager: false)
        Intake::Placement.new(person: person, registration: registration).apply!
        nil
      end
    end
  end

  def applicant_member!(person)
    entry.household_members.find_or_create_by!(person: person, role: :applicant) do |member|
      match = Intake.possible_match(first_name: person.first_name, last_name: person.last_name, birthday: person.birthday, except: person.id)
      member.facts = { "possible_match_id" => match&.id }.compact
    end
  end

  # Someone the entry's person adds ("Anyone else joining with them?"). The
  # same name twice in one household is refused; a match with someone
  # outside it is only noted for staff. Linked as the adder's ward through
  # the registration's guardianship type.
  def add_ward(adder:, first_name:, last_name:, birthday: nil, teams: entry.teams)
    raise Refused, "This registration doesn't take family members." unless registration.guardian_relationship_type
    first_name = first_name.to_s.strip
    last_name = last_name.to_s.strip
    raise Refused, "Enter a first and last name." if first_name.blank? || last_name.blank?
    raise Refused, "#{first_name} #{last_name} is already on this sign-up." if household_has_name?(first_name, last_name)

    Person.transaction do
      ward = Person.create!(first_name: first_name, last_name: last_name, birthday: birthday)
      match = Intake.possible_match(first_name: first_name, last_name: last_name, birthday: birthday, except: [ ward.id ] + entry.household_people.ids)
      entry.household_members.create!(person: ward, role: :ward, facts: { "possible_match_id" => match&.id }.compact)
      link_guardian(guardian: adder, ward: ward)
      apply(ward, teams)
      ward
    end
  end

  # A young person names a guardian: held on a guardian row until the
  # guardian opens their link. Returns [row, token].
  def name_guardian(ward:, first_name:, last_name:, email:)
    raise Refused, "This registration doesn't take guardians." unless registration.guardian_relationship_type
    email = Intake.normalize_email(email)
    raise Refused, "Enter your guardian's name and email." if first_name.blank? || last_name.blank? || email.blank?
    raise Refused, "Enter a valid email." unless email.match?(URI::MailTo::EMAIL_REGEXP)
    if entry.household_members.guardian.any? { |member| member.facts["ward_id"] == ward.id && member.facts["email"] == email }
      raise Refused, "That guardian is already on this sign-up."
    end

    row = entry.household_members.create!(role: :guardian, facts: {
      "ward_id" => ward.id, "first_name" => first_name.to_s.strip, "last_name" => last_name.to_s.strip, "email" => email
    })
    [ row, row.issue_token! ]
  end

  # The guardian opened their link. An existing login is linked; otherwise
  # a person and login are made (the caller sets the password).
  def confirm_guardian(row, guardian)
    Person.transaction do
      link_guardian(guardian: guardian, ward: row.ward)
      row.update!(person: guardian, guardian_confirmed_at: Time.current, token_digest: nil)
      # Placement adds guardians on approval; one who confirms afterwards
      # joins the guardian teams now.
      if row.ward.membership_applications.approved.exists?(registration: registration)
        Intake::Placement.new(person: row.ward, registration: registration).add_guardians_to_teams
      end
    end
  end

  # The guardianship tie. Intake makes it from the household's shape or a
  # guardian's own confirmation, never from someone typing it, so the
  # type's "added by" rule (which is about members adding ties by hand)
  # doesn't apply.
  def link_guardian(guardian:, ward:)
    type = registration.guardian_relationship_type
    return if type.nil? || guardian.nil? || ward.nil? || guardian == ward
    return if Relationship.exists?(relationship_type: type, parent: guardian, child: ward)
    Relationship.new(relationship_type: type, parent: guardian, child: ward).save!(validate: false)
  end

  private

  def household_has_name?(first_name, last_name)
    key = [ first_name.downcase, last_name.downcase ]
    names = entry.household_people.pluck(:first_name, :last_name).map { |f, l| [ f.to_s.strip.downcase, l.to_s.strip.downcase ] }
    names << [ entry.first_name.to_s.strip.downcase, entry.last_name.to_s.strip.downcase ]
    names.include?(key)
  end
end
