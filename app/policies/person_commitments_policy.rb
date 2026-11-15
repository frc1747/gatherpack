# A person's commitments page. The person sees every commitment they owe and
# those owed by a group they're related to; others see only the ones they
# run (Commitment#organizer?) or whose group they're related to through its
# relationship type, so they see progress and nothing more of the person.
class PersonCommitmentsPolicy < ApplicationPolicy
  def show?
    return false if person.nil?

    person.id == record.id || visible_commitments.any?
  end

  # The commitments covering record (a Person) that the viewer may see.
  def visible_commitments
    return [] if person.nil?

    commitments = Commitment.includes(:team, :owing_team).order(:starts_on, :title).to_a
    if person.id == record.id
      return commitments.select { |commitment| commitment.covers?(record) || commitment.group_relative?(record) }
    end

    commitments.select do |commitment|
      commitment.covers?(record) && (commitment.organizer?(person) || commitment.group_relative_of?(person, record))
    end
  end
end
