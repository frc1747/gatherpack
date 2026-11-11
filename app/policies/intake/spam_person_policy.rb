# Deleting a person who came in through a registration and was denied as
# spam, with their login: admins only, and only while the person has
# nothing else (Intake::SpamPerson#deletable?).
class Intake::SpamPersonPolicy < ApplicationPolicy
  def show?
    user&.admin && Intake::SpamPerson.new(record).deletable?
  end

  def destroy?
    show?
  end
end
