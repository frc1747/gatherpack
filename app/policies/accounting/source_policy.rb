# What people may do with an accounting source beyond the gateway pages
# (architects only). Connecting and disconnecting signs GatherPack in to
# the books, so it's for architects; syncing and reading the copied
# records is for admins and architects (whose hook and report code already
# sees every record).
class Accounting::SourcePolicy < ApplicationPolicy
  def connect?
    user&.architect == true
  end

  def disconnect?
    connect?
  end

  def sync?
    reader?
  end

  def records?
    reader?
  end

  private
    def reader?
      user&.admin == true || user&.architect == true
    end
end
