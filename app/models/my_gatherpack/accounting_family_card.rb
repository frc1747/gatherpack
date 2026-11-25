# A Family page ward card that knows whether it has account rows, so it
# isn't called empty when they're all it shows.
module MyGatherpack::AccountingFamilyCard
  attr_writer :accounting

  def empty?
    super && !@accounting
  end
end
