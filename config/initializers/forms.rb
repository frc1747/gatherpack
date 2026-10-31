# A profile change can make a form's signed "updates profile" answer stale.
# Re-sync those responses: they show "changed since signed", and on forms
# that ask for it, need re-confirmation (and lose the completion badge).
ActiveSupport::Notifications.subscribe("person_field_changed.gatherpack") do |*, payload|
  change = payload[:change]
  Form.resync_profile_field!(change.person, change.field)
end

Rails.application.config.to_prepare do
  # A form's completion badge can't be given access to person fields either
  # (FormCompletionBadgeGuard).
  PersonFieldBadgeGrant.include(FormCompletionBadgeGuard)

  # Form grants count only while their badge is admin-assigned and its team
  # (if any) exists, and such a badge can't be relaxed while it has form
  # grants. See BadgeAccessGrants.
  Badge.include(BadgeAccessGrants)
  Badge.has_many :form_badge_grants, inverse_of: :badge
  Badge.register_access_grants(:form_badge_grants)
end
