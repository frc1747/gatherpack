# A device belongs to the login that turned notifications on, so when two
# logins merge the removed login's devices and topic choices go with it.
# GatherPack::PersonMerge is required by its own initializer, and to_prepare
# runs after every initializer has loaded, so file order doesn't matter.
Rails.application.config.to_prepare do
  next unless defined?(GatherPack::PersonMerge)

  merge = GatherPack::PersonMerge

  merge.register :push_subscriptions, :user_id, owner: :user, action: :delete, label: "Phones getting notifications"
  merge.register :push_preferences, :user_id, owner: :user, action: :delete, label: "Notification choices"
end
