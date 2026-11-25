# How a purchase was paid: a team card, someone's own money and so on. A
# managed list (GatherPack::ManagedLists): admins add, rename, reorder and
# retire them. One marked reimburse means the buyer is paid back. At least
# one stays active, so Record purchase always has a choice.
class PaymentMethod < ApplicationRecord
  include ManagedList
  has_neat_id :pmt
  managed_list uses: { purchases: :payment_method_id }

  has_many :purchases, dependent: :restrict_with_error

  LAST_ONE = "is the only active payment method. Add or restore another before retiring or deleting it.".freeze

  validate :another_active_one, if: -> { persisted? && will_save_change_to_active?(from: true, to: false) }
  before_destroy :keep_another_active, prepend: true

  def identifier_icon
    "credit-card"
  end

  def identifier_name
    name
  end

  private

  def others_active?
    self.class.active.where.not(id: id).exists?
  end

  def another_active_one
    errors.add(:base, "#{name_was} #{LAST_ONE}") unless others_active?
  end

  def keep_another_active
    return if !active? || others_active?

    errors.add(:base, "#{name} #{LAST_ONE}")
    throw :abort
  end
end
