# Everyone signed in sees vendors (to pick one on a request); buyers (a
# buyer row reaching any team) and admins manage them and see account
# notes.
class VendorPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      person.present? ? scope.all : scope.none
    end
  end

  def index?
    person.present?
  end

  def show?
    person.present?
  end

  def create?
    manages_vendors?
  end

  def update?
    manages_vendors?
  end

  def destroy?
    manages_vendors?
  end

  def account_note?
    manages_vendors?
  end

  private

  def manages_vendors?
    return false if person.nil?

    access = Orders::Access.for(person)
    access.buyer?
  end
end
