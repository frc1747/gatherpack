Rails.application.config.to_prepare do
  # Person field grants count only while their badge is admin-assigned and
  # its team (if any) exists. See BadgeAccessGrants.
  Badge.include(BadgeAccessGrants)
  Badge.has_many :person_field_badge_grants, inverse_of: :badge
  Badge.register_access_grants(:person_field_badge_grants)
end
