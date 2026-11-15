# Order notices: the timeline entry that sends them, and the status change
# that does (see Orders::EventNotices). Uses config.to_prepare like the
# orders initializer so the patch comes back after a development reload.
Rails.application.config.to_prepare do
  OrderRequestEvent.include(Orders::EventNotices)
  Orders::EventNotices.subscribe!
end
