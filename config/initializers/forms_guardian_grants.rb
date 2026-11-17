# Lists what forms let a guardian do on the relationship type pages, beside
# what person fields grants (RelationshipType.register_guardian_grant).
Rails.application.config.to_prepare do
  forms_on = -> { GatherPack::Features.enabled?(:forms) }
  RelationshipType.register_guardian_grant("fill in forms for the child and sign consent as their guardian", if: forms_on)
  RelationshipType.register_guardian_grant("get form reminders about the child", if: forms_on)
end
