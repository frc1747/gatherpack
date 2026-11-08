# Commitments' settings, hook events and credit source kinds. Uses
# config.to_prepare (like features.rb) so the source registry, which lives in
# reloadable app/ code, is filled again after each development reload.
#
# Another branch adds a credit source kind from its own initializer:
#
#   Rails.application.config.to_prepare do
#     Commitments.register_source(:signups, Commitments::SignupSource)
#   end
Rails.application.config.to_prepare do
  Settings.register(:commitments_organizers, :text, "Commitment Organizers", "", "Commitments",
    "Who may create and run commitments without managing a team. One per line, as Badge name > Highest team name. " \
    "Holders of the badge (one only admins assign) can run commitments for the teams they belong to at or below that team, " \
    "and the teams below their own. Leave out \"> Highest team name\" to allow only the teams they're directly in and the teams below those")

  GatherPack::HookCatalog.register_targets("commitments", "commitment_organizers", "commitment_sources", "commitment_adjustments")

  Commitments.register_source(:checkins, Commitments::CheckinSource)

  # A commitment's team, owing team, owing and exempt badges and group
  # relationship type can't be deleted while it uses them: losing the owing
  # badge would widen who owes, losing the exempt badge would make the
  # exempt owe, and losing the type would split groups. The foreign keys
  # block it too; these give a readable error instead.
  Badge.has_many :owing_commitments, class_name: "Commitment", foreign_key: :owing_badge_id, inverse_of: :owing_badge, dependent: :restrict_with_error
  Badge.has_many :exempting_commitments, class_name: "Commitment", foreign_key: :exempt_badge_id, inverse_of: :exempt_badge, dependent: :restrict_with_error
  RelationshipType.has_many :grouping_commitments, class_name: "Commitment", foreign_key: :group_relationship_type_id,
    inverse_of: :group_relationship_type, dependent: :restrict_with_error
  Team.has_many :commitments, inverse_of: :team, dependent: :restrict_with_error
  Team.has_many :owed_commitments, class_name: "Commitment", foreign_key: :owing_team_id, inverse_of: :owing_team, dependent: :restrict_with_error
end
