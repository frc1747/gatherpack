# A profile change can make a form's signed "updates profile" answer stale.
# Re-sync those responses: they show "changed since signed", and on forms
# that ask for it, need re-confirmation (and lose the completion badge).
ActiveSupport::Notifications.subscribe("person_field_changed.gatherpack") do |*, payload|
  change = payload[:change]
  Form.resync_profile_field!(change.person, change.field)
end

# A form's completion badge can't be given access to person fields either
# (FormCompletionBadgeGuard).
Rails.application.config.to_prepare do
  PersonFieldBadgeGrant.include(FormCompletionBadgeGuard)
end
