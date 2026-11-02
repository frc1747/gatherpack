require_relative "mcp_world"

# Commitments for the MCP commitment tools, on top of McpWorld (call
# build_mcp_world first, then build_mcp_commitments_world). Includes
# McpWorld and turns the commitments feature on for each test.
#
#   "Shifts": Alpha runs it and owes it, 2 shifts each, grouped by "Parent of"
#   (1 more for each other member), counted by check-ins at any event of the
#   event type. alpha_member checked in at a past event (confirmed), ward at
#   an upcoming one (planned); guardian, in no team, is ward's relative.
#   organizer is in Alpha with the "Commitment Organizer" badge, granted for
#   Alpha, and on the commitment's organizer list; alpha_manager manages Alpha.
#   "Beta Shifts": Beta runs it and owes it. "Last Year": Alpha's, already ended.
module McpCommitmentsWorld
  def self.included(base)
    base.include McpWorld
    base.setup { @restore_commitments_feature = apply_settings(feature_commitments: "true") }
    base.teardown { @restore_commitments_feature&.call }
  end

  def build_mcp_commitments_world
    @people[:organizer] = create_world_person("Organizer", @alpha)
    @organizer_badge = create_world_badge("Commitment Organizer")
    BadgeAssignment.create!(badge: @organizer_badge, person: person(:organizer))
    Settings[:commitments_organizers] = "Commitment Organizer > Alpha"

    @shifts = Commitment.create!(title: "Shifts", team: @alpha, owing_team: @alpha, base_amount: 2, additional_amount: 1, unit: "shifts",
      group_relationship_type: @parent_of, starts_on: 1.month.ago.to_date, ends_on: 1.month.from_now.to_date)
    @shifts.commitment_organizers.create!(person: person(:organizer))
    @shifts.commitment_sources.create!(kind: "checkins", subject: event_types(:one))
    @beta_shifts = Commitment.create!(title: "Beta Shifts", team: @beta, owing_team: @beta, base_amount: 1, unit: "shifts",
      starts_on: 1.month.ago.to_date, ends_on: 1.month.from_now.to_date)
    @last_year = Commitment.create!(title: "Last Year", team: @alpha, owing_team: @alpha, base_amount: 1, unit: "shifts",
      starts_on: 1.year.ago.to_date, ends_on: 6.months.ago.to_date)

    past = create_world_event("Past Shift", @alpha, 3.days.ago)
    upcoming = create_world_event("Next Shift", @alpha, 3.days.from_now)
    create_world_checkin(person(:alpha_member), past)
    create_world_checkin(person(:ward), upcoming)
  end
end
