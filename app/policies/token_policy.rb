class TokenPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin
        scope.all
      else
        # A card's value is what logs its holder in at the kiosk, so list only
        # the cards the user may change (the people ApplicationPolicy#manages?
        # accepts), plus their own.
        managed_team_ids = person.all_managed_teams.ids
        privileged = Person.joins(:user).where(users: { admin: true }).or(Person.joins(:user).where(users: { architect: true }))
        managers_elsewhere = Membership.where(manager: true).where.not(team_id: managed_team_ids)
        managed = Person.joins(:memberships).where(memberships: { team_id: managed_team_ids })
          .where.not(id: privileged.select(:id))
          .where.not(id: managers_elsewhere.select(:person_id))

        scope.where(tokenable_type: "Person", tokenable_id: managed.select(:id)).or(scope.where(tokenable: person))
      end
    end
  end

  def new?
    user.admin? || person.manager?
  end

  def create?
    user.admin? || manages_holder?
  end

  def edit?
    update?
  end

  def update?
    create?
  end

  def destroy?
    create?
  end

  private

  # A card stands in for its holder at the kiosk, so a manager may only issue
  # or change one for someone they manage, or for themselves. Cards held by
  # anything other than a person are left to admins.
  def manages_holder?
    holder = record.tokenable
    return false unless holder.is_a?(Person)

    holder == person ? person.manager? : manages?(holder)
  end
end
