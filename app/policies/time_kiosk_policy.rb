# The time kiosk clocks in and out whoever's card is scanned, so it runs only
# on kiosk accounts (which admins grant) and for admins.
class TimeKioskPolicy < ApplicationPolicy
  def use?
    user.present? && (user.kiosk? || user.admin?)
  end
end
