# Housekeeping's pages. Anyone signed in may open the bulk bar on a list
# they can see; each record is then checked on its own (Housekeeping::Type
# #permitted?). Retention purges are for admins only.
class HousekeepingPolicy < ApplicationPolicy
  def change?
    person.present?
  end

  def purge?
    user.admin?
  end
end
