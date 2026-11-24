# Orders' columns that point at a person, registered where people can be
# merged (GatherPack::PersonMerge); without it there's nothing to register.
# GatherPack::PersonMerge is required by its own initializer, and to_prepare
# runs after every initializer has loaded, so file order doesn't matter.
Rails.application.config.to_prepare do
  next unless defined?(GatherPack::PersonMerge)

  merge = GatherPack::PersonMerge

  merge.register :order_requests, :requested_by_id, label: "Order requests"
  merge.register :order_approvals, :approver_id, label: "Order approvals"
  merge.register :order_request_events, :actor_id, label: "Order history"
  merge.register :order_request_watchers, :person_id, unique_by: :order_request_id, model: OrderRequestWatcher,
    label: "Order requests followed"
  merge.register :purchases, :buyer_id, label: "Purchases made"
  merge.register :purchases, :reimburse_to_id, label: "Purchases to pay back"
  merge.register :order_deliveries, :received_by_id, label: "Deliveries received"
  # One row for each person: the kept person's choice stands, the other goes.
  merge.register :order_notice_preferences, :person_id, action: :delete, model: OrderNoticePreference,
    label: "Order notice choices"
  # The day Orders' own summary last went out: the kept person's stands.
  merge.register :order_summary_sends, :person_id, action: :delete, model: OrderSummarySend,
    label: "Orders summary sends"

  # Polymorphic: points at an inventory item, never a person or a login.
  reason = "item_type/item_id points at inventory items, never a person or login"
  merge.exempt :order_lines, :item_id, reason: reason
  merge.exempt :order_lines, :item_id, reason: reason, owner: :user
end
