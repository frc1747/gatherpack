# What people may do with an accounting source beyond the gateway pages
# (architects only). Connecting and disconnecting signs GatherPack in to
# the books, so it's for architects; syncing and reading the copied
# records is for admins and architects (whose hook and report code already
# sees every record). Linking customers to people decides who sees whose
# money, so it's for admins and holders of the customer matching badge,
# who may also run Sync now (a read from the source) from the Customers
# page so they needn't wait for the next scheduled check. Uploading a file source's records is a sync,
# for admins and architects; such a source is never synced any other way.
class Accounting::SourcePolicy < ApplicationPolicy
  def connect?
    user&.architect == true
  end

  def disconnect?
    connect?
  end

  # A source whose records come from uploads has nothing to sync: a sync
  # would only mark it as if a file were applied.
  def sync?
    (reader? || customers?) && !record.capabilities.include?(:upload)
  end

  # Reading every record again: Records page buttons, not for matchers.
  def full_sync?
    reader? && !record.capabilities.include?(:upload)
  end

  def records?
    reader?
  end

  def customers?
    Accounting::Access.customer_matcher?(user)
  end

  # Uploading a file source's records, like syncing a connected source.
  def upload?
    reader? && record.capabilities.include?(:upload)
  end

  private
    def reader?
      user&.admin == true || user&.architect == true
    end
end
