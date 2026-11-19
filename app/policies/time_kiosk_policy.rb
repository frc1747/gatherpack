# The time kiosk clocks in and out whoever's card is scanned, so it runs only
# on kiosk accounts (which admins grant), for admins, and for members of the
# kiosk users team when one is set.
class TimeKioskPolicy < ApplicationPolicy
  def use?
    return false if user.nil?
    return true if user.kiosk? || user.admin?

    team = TimeKiosk::Config.users_team
    team.present? && person.present? && person.teams.exists?(id: team.id)
  end
end
