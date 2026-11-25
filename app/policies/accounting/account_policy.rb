# A person's Account tab and statement. record is the person whose account
# it is. The tab shows when the viewer may see at least one of that
# person's results, or may match customers by reference (to copy the
# person's id); the statement when they may see amounts for one.
class Accounting::AccountPolicy < ApplicationPolicy
  def show?
    Accounting::Access.sees_account_tab?(user, record)
  end

  def statement?
    user&.person.present? && Accounting::Statement.new(user.person, record).visible?
  end

  # Customer links, descriptions and "Open in" links.
  def manage_links?
    user&.admin == true
  end
end
