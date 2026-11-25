# What people may do with an accounting source beyond the gateway pages
# (architects only). Connecting and disconnecting signs GatherPack in to
# the books, so it's for architects; syncing and reading the copied
# records is for admins.
class Accounting::SourcePolicy < ApplicationPolicy
  def connect?
    user&.architect == true
  end

  def disconnect?
    connect?
  end

  def sync?
    user&.admin == true
  end

  def records?
    user&.admin == true
  end
end
