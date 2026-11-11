class PersonPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin
        scope.all
      else
        scope.where(id: (person.all_teams.map(&:all_people).flatten.map(&:id) << person.id) + person.wards.ids).distinct
      end
    end
  end

  def show?
    record == person || user.admin? || (person.all_teams & record.all_teams).any? || person.wards.include?(record)
  end

  # The extra read-only member pages share the same visibility rule as #show.
  alias_method :recent_activity?, :show?
  alias_method :calendar?, :show?
  alias_method :statistics?, :show?
  alias_method :relationships?, :show?
  alias_method :teams?, :show?

  # Who may edit the base profile (name, bio, avatar, built-in details).
  def update_profile?
    record == person || user.admin? || (person.all_managed_teams & record.all_teams).any?
  end

  # Someone who can write a person field (a guardian, say) can reach the
  # edit form too, but only sees the fields they can write.
  def update?
    update_profile? || writable_person_fields.any?
  end

  def readable_person_fields
    @readable_person_fields ||= record.readable_fields_for(person)
  end

  def writable_person_fields
    @writable_person_fields ||= record.writable_fields_for(person)
  end

  def destroy?
    user.admin?
  end

  def impersonate?
    user.admin?
  end

  def stop_impersonating?
    user.admin?
  end
end
