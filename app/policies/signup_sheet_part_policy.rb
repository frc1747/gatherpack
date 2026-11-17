# The parts of a sheet (positions and their rules, organizers, audience
# rules, events and slots) are run by the sheet's organizers.
class SignupSheetPartPolicy < ApplicationPolicy
  def index?
    manage?
  end

  def show?
    manage?
  end

  def create?
    manage?
  end

  def update?
    manage?
  end

  def destroy?
    manage?
  end

  private

  def manage?
    SignupSheetPolicy.new(user, record.signup_sheet).manage?
  end
end
