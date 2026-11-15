class Membership < ApplicationRecord
  has_neat_id :mbr
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :person
  belongs_to :team

  validates :person, uniqueness: { scope: :team, message: "is already a member of this team" }

  # A team badge needs its holder in the team. Removing a team or a person
  # handles its own memberships (see Team and Person).
  after_destroy :recheck_badges, unless: :destroyed_by_association
  after_update :recheck_badges, if: -> { saved_change_to_person_id? || saved_change_to_team_id? || saved_change_to_manager? }
  before_commit :remove_badges_outside_team, if: -> { @recheck_person_ids }

  def self.ransackable_attributes(auth_object = nil)
    attributes = [ "manager", "person.display_name", "person.last_name", "person.first_name", "updated_at" ]
    attributes << "person.birthday" if Person.ransackable_attributes(auth_object).include?("birthday")
    attributes
  end

  def self.ransackable_associations(auth_object = nil)
    [ "person" ]
  end

  def identifier_icon
  end

  def identifier_name
    "#{person.display_name} => #{team.name}"
  end

  private

  def recheck_badges
    @recheck_person_ids = [ person_id, person_id_before_last_save ].compact.uniq
  end

  # Checked just before the transaction commits, so a change that moves the
  # badge in the same transaction (merging two people, say) is seen whole,
  # and a failed removal rolls the membership change back.
  def remove_badges_outside_team
    person_ids, @recheck_person_ids = @recheck_person_ids, nil
    BadgeAssignment.remove_outside_team(BadgeAssignment.where(person_id: person_ids))
  end
end
