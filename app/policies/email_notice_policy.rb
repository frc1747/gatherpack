# Everyone signed in chooses their own email notices, and only their own:
# the page always works on the signed-in person.
class EmailNoticePolicy < ApplicationPolicy
  def show?
    person.present?
  end

  def update?
    show?
  end

  def index?
    false
  end

  def create?
    false
  end

  def destroy?
    false
  end
end
