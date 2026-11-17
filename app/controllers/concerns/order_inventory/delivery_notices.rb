# Included into Orders::DeliveriesController: a delivery is recorded even
# when putting it away into inventory couldn't be done; this says why.
module OrderInventory
  module DeliveryNotices
    extend ActiveSupport::Concern

    included do
      after_action :order_inventory_problems, only: :create
    end

    private

    def order_inventory_problems
      problems = OrderInventory::Current.problems
      flash[:alert] = problems.join(" ") if problems.any?
    end
  end
end
