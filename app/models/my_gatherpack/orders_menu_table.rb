module MyGatherpack
  # Places the Purchasing pages that run orders in Manage for team managers.
  # The core assigns the whole table when its initializer runs, which can be
  # after this branch's, so the entries are merged in on every assignment.
  module OrdersMenuTable
    ENTRIES = {
      orders_approvals_path: { manage: 120 },
      to_buy_orders_purchases_path: { manage: 130 },
      orders_vendors_path: { manage: 140 },
      orders_funding_sources_path: { manage: 150 },
      orders_reports_path: { manage: 160 }
    }.freeze

    def table=(value)
      super(ENTRIES.merge(value || {}))
    end
  end
end
