require_relative "mcp_world"

# Commitments for the MCP commitment tools, on top of McpWorld (call
# build_mcp_world first, then build_mcp_commitments_world). Includes
# McpWorld and turns the commitments feature on for each test.
#
#   "Shifts": Alpha runs it and owes it, 2 shifts each, grouped by "Parent of"
#   (1 more for each other member), counted by check-ins at any event of the
#   event type. alpha_member checked in at a past event (confirmed), ward at
#   an upcoming one (planned); guardian, in no team, is the parent of ward and
#   sibling (one group, who owe 3 together), checked in to "Parent Shift", and
#   ward has a +1 "Covered a shift" adjustment. beta_member is a "Friend of"
#   alpha_member (not the group type). lapsed is in Alpha and on the organizer
#   list but lost the badge, so doesn't run it.
#   organizer is in Alpha with the "Commitment Organizer" badge, granted for
#   Alpha, and on the commitment's organizer list; alpha_manager manages Alpha.
#   "Beta Shifts": Beta runs it and owes it. "Last Year": Alpha's, already ended.
module McpCommitmentsWorld
  def self.included(base)
    base.include McpWorld
    base.setup { @restore_commitments_feature = apply_settings(feature_commitments: "true", commitments_organizers: "Commitment Organizer > Alpha") }
    base.teardown { @restore_commitments_feature&.call }
  end

  def build_mcp_commitments_world
    @people[:organizer] = create_world_person("Organizer", @alpha)
    @organizer_badge = create_world_badge("Commitment Organizer")
    BadgeAssignment.create!(badge: @organizer_badge, person: person(:organizer))

    @people[:sibling] = create_world_person("Sibling", @alpha)
    Relationship.create!(parent: person(:guardian), child: person(:sibling), relationship_type: @parent_of, created_by: person(:admin))
    @people[:lapsed] = create_world_person("Lapsed", @alpha)
    @friend = RelationshipType.create!(parent_label: "Friend of", child_label: "Friend of", permission: :added_by_admin)
    Relationship.create!(parent: person(:beta_member), child: person(:alpha_member), relationship_type: @friend, created_by: person(:admin))

    @shifts = Commitment.create!(title: "Shifts", team: @alpha, owing_team: @alpha, base_amount: 2, additional_amount: 1, unit: "shifts",
      group_relationship_type: @parent_of, starts_on: 1.month.ago.to_date, ends_on: 1.month.from_now.to_date)
    @shifts.commitment_organizers.create!(person: person(:organizer))
    lapsed_badge = BadgeAssignment.create!(badge: @organizer_badge, person: person(:lapsed))
    @shifts.commitment_organizers.create!(person: person(:lapsed))
    lapsed_badge.destroy!
    @shifts.commitment_sources.create!(kind: "checkins", subject: event_types(:one))
    @beta_shifts = Commitment.create!(title: "Beta Shifts", team: @beta, owing_team: @beta, base_amount: 1, unit: "shifts",
      starts_on: 1.month.ago.to_date, ends_on: 1.month.from_now.to_date)
    @last_year = Commitment.create!(title: "Last Year", team: @alpha, owing_team: @alpha, base_amount: 1, unit: "shifts",
      starts_on: 1.year.ago.to_date, ends_on: 6.months.ago.to_date)

    past = create_world_event("Past Shift", @alpha, 3.days.ago)
    upcoming = create_world_event("Next Shift", @alpha, 3.days.from_now)
    create_world_checkin(person(:alpha_member), past)
    create_world_checkin(person(:ward), upcoming)
    create_world_checkin(person(:guardian), create_world_event("Parent Shift", @alpha, 2.days.ago))
    CommitmentAdjustment.create!(commitment: @shifts, person: person(:ward), credits: 1, reason: "Covered a shift", created_by: person(:organizer))
  end
end
