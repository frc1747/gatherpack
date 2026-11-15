class TimeClockPunchPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin
        scope.all
      elsif person.manager?
        scope.where(person: (person.all_managed_teams.map(&:person_ids).flatten << person.id).uniq)
      else
        scope.where(person: person)
      end
    end
  end

  def flagged?
    user.admin || person.manager?
  end

  def update_max_hours?
    user.admin
  end

  def bulk_destroy?
    user.admin || person.manager?
  end

  # Admins record punches for anyone, members for themselves and managers for
  # the people they manage, within what the period allows (see update?). In an
  # 'added_by_team_member' period the team's members record for each other, as
  # before. The empty new form has no person yet; saving a punch without one
  # fails validation.
  def create?
    return false unless may_enter_punches?
    return true if record.person.nil?

    (user.admin || person == record.person || manages?(record.person) || team_member_period?) && update?
  end

  def update?
    return false unless may_enter_punches?

    # can update punches if admin or punch is not part of any period, i.e. added by self
    if user.admin || (person == record.person && record.time_clock_period.nil?)
      true
    # can update punches if part of a generic period with 'added_by_user' perms
    elsif record.time_clock_period.nil?
      person == record.person || manages?(record.person)
    elsif record.time_clock_period.team.nil?
      person == record.person && record.time_clock_period.permission == "added_by_user"
    # can update punches if manager of punch's period's team, up to 'added_by_manager' perms
    elsif person.all_managed_teams.include?(record.time_clock_period.team)
      record.time_clock_period.permission != "added_by_admin"
    # can update punches if part of punch's period's team and the period has 'added_by_team_member' perms, or if 'added_by_user' perms, and the punch was added by self
    else
      (person.all_teams.include?(record.time_clock_period.team) && record.time_clock_period.permission == "added_by_team_member") || (person == record.person && record.time_clock_period.permission == "added_by_user")
    end
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  private

  # With the setting on, a member who manages no team has no hand entry at all.
  # This is the rule for the Time Clock pages only: the kiosk doesn't use this
  # policy, so members still clock in and out there.
  def may_enter_punches?
    !Settings[:time_clock_hand_punches_managers_only] || user.admin || person.manager?
  end

  def team_member_period?
    period = record.time_clock_period
    period&.team.present? && period.permission == "added_by_team_member" && person.all_teams.include?(period.team)
  end
end
