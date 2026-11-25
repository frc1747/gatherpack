# frozen_string_literal: true

# Only admins pair, rename and revoke kiosk devices.
class KioskDevicePolicy < AdminPolicy
  def revoke?
    update?
  end

  def pair?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.admin ? scope.all : scope.none
    end
  end
end
