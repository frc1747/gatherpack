# A person's commitments page. The person sees every commitment they owe;
# others see only the ones they run (Commitment#organizer?), so organizers
# see progress and nothing more of the person.
class PersonCommitmentsPolicy < ApplicationPolicy
  def show?
    return false if person.nil?

    person.id == record.id || visible_commitments.any?
  end

  # The commitments covering record (a Person) that the viewer may see.
  def visible_commitments
    return [] if person.nil?

    owed = Commitment.includes(:team, :owing_team).order(:starts_on, :title).select { |commitment| commitment.covers?(record) }
    return owed if person.id == record.id

    owed.select { |commitment| commitment.organizer?(person) }
  end
end
