class TeamPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin
        scope.all
      else
        scope.where(id: person.all_team_ids)
          .or(scope.where(join_permission: Team.join_permissions[:has_account]))
          .or(scope.where(join_permission: Team.join_permissions[:requires_approval]))
      end
    end
  end

  # The same records Scope lists, which is how the controller loads them.
  def show?
    Scope.new(user, Team).resolve.exists?(record.id)
  end

  def new?
    person.manager?
  end

  # Managers create teams only under a team they manage; top-level teams are
  # for admins.
  def create?
    user.admin? || manages?(record.parent)
  end

  # Checked with the new parent assigned. A manager moves a team only from
  # under one team they manage to another, so they can't take it away from a
  # team above them; making a team top-level, or moving one that is, is for
  # admins.
  def move?
    user.admin? || (manages?(Team.find_by(id: record.parent_id_was)) && manages?(record.parent))
  end

  def update?
    has_perms
  end

  def destroy?
    update?
  end

  def badges?
    show?
  end

  def pages?
    show?
  end

  def events?
    show?
  end

  # Pending applications name the applicants, so only managers see them.
  def applications?
    has_perms
  end

  def manage_members?
    has_perms
  end

  # The full team page, rather than show_public. Managers of a parent team
  # manage this team too, so they get it without being direct members.
  def show_full?
    user.admin || user.architect || record.people.include?(person) || has_perms
  end

  # Managers add and remove people through memberships, which check who they
  # may add; person_ids would replace the whole list unchecked.
  def permitted_attributes_for_update
    [ :name, :color, :team_type_id, :description ] + if user.admin?
      [ :join_permission, :parent_id, person_ids: [] ]
    elsif record.join_permission != "added_by_admin"
      [ :parent_id ]
    else
      []
    end
  end

  private

  def has_perms
    user.admin || record.all_managers_and_admins.include?(user.person)
  end
end
