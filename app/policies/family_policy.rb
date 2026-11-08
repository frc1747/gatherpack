class FamilyPolicy < ApplicationPolicy
  def show?
    person.present? && person.wards.exists?
  end
end
