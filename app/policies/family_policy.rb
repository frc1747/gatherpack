class FamilyPolicy < ApplicationPolicy
  def show?
    person.present? && person.wards.any?
  end
end
