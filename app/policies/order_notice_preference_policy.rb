# Only someone who has a To buy list (a buyer, a team manager or an admin)
# has a choice to make, and only about their own notices.
class OrderNoticePreferencePolicy < ApplicationPolicy
  def edit?
    person.present? && Orders::Access.for(person).buyer?
  end

  def update?
    edit?
  end

  def show?
    false
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
