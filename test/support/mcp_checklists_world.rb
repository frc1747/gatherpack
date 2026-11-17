require_relative "mcp_world"

# A checklist for the MCP checklist tools, on top of McpWorld (call build_mcp_world first, then
# build_mcp_checklists_world). Includes McpWorld and turns checklists on for each test, with
# the checklist organizers setting naming the "Checklist Organizer" badge for Alpha.
#
#   Alpha ─ Crew: crew_lead (manager of Crew only), alpha_member (also in Alpha)
#   "Eligibility" runs on Alpha, covers Alpha and below. Items: "Login" (a condition), "Shifts"
#   (count, 2 shifts, from check-ins; alpha_member has 1), "Handbook" (confirmed by a guardian
#   or the person) and "Safety" (badge).
#
#   subject      alpha_member (covered, in Crew)
#   guardian     kid_parent: guardian of kid (in Alpha, under 18, minor guardianship)
#   leader       crew_lead: manages Crew, so leads alpha_member, but not the checklist's team
#   grant_holder holds the "Report Viewer" badge; the checklist's full grant covers every item
#   organizer    in the checklist's organizer list, holds the "Checklist Organizer" badge
#   alpha_manager manages Alpha, so runs the checklist; admin runs everything
#   stranger     beta_member, in Beta
module McpChecklistsWorld
  def self.included(base)
    base.include McpWorld
    base.setup do
      @restore_checklists_feature = apply_settings(feature_checklists: "true", feature_badges: "true",
        checklists_organizers: "Checklist Organizer > Alpha")
    end
    base.teardown { @restore_checklists_feature&.call }
  end

  def build_mcp_checklists_world
    @crew = create_world_team("Crew", parent: @alpha)
    @people[:crew_lead] = create_world_person("CrewLead", @crew, manager: true)
    Membership.create!(person: person(:alpha_member), team: @crew)
    @people[:kid] = create_world_person("Kid", @alpha)
    person(:kid).update!(birthday: 10.years.ago.to_date)
    @people[:kid_parent] = create_world_person("KidParent")
    @guardianship = RelationshipType.create!(parent_label: "Guardian of", child_label: "Ward of", permission: :added_by_admin, guardianship: :minor)
    Relationship.create!(parent: person(:kid_parent), child: person(:kid), relationship_type: @guardianship, created_by: person(:admin))
    @people[:organizer] = create_world_person("Organizer", @alpha)
    @people[:grant_holder] = create_world_person("GrantHolder")

    @organizer_badge = create_world_badge("Checklist Organizer")
    BadgeAssignment.create!(badge: @organizer_badge, person: person(:organizer))
    @viewer_badge = create_world_badge("Report Viewer")
    BadgeAssignment.create!(badge: @viewer_badge, person: person(:grant_holder))
    @safety = create_world_badge("Safety 2026")

    @checklist = Checklist.create!(title: "Eligibility", team: @alpha, status: :active, starts_on: Date.current - 2.months,
      ends_on: Date.current + 6.months, created_by: person(:admin))
    @checklist.checklist_rules.create!(effect: :include, target_type: :team, team: @alpha)
    @checklist.checklist_organizers.create!(person: person(:organizer))

    @login = add_checklist_item(:has_login, "Login")
    @shifts = add_checklist_item(:count, "Shifts", { base_amount: 2, unit: "shifts" })
    @shifts.commitment.commitment_sources.create!(kind: "checkins", subject: event_types(:one))
    @handbook = add_checklist_item(:attested, "Handbook", { statement: "Handbook read", attested_by: "guardian" })
    @safety_item = add_checklist_item(:badge, "Safety", { badge_ids: [ @safety.id ] })
    @checklist.checklist_grants.create!(badge: @viewer_badge, access: :full, item_ids: [ @login, @shifts, @handbook, @safety_item ].map(&:id))

    create_world_checkin(person(:alpha_member), create_world_event("Shift one", @alpha, Time.current - 3.days))
    refresh_checklist
  end

  # Stores everyone's results, as the refresh job does: the checklists list and the page find a
  # checklist through them.
  def refresh_checklist
    Checklists::Refresher.new(@checklist.reload, silent: true).call
  end

  def add_checklist_item(kind, label, config = {}, **attributes)
    item = @checklist.checklist_items.new({ kind: kind.to_s, label: label }.merge(attributes))
    item.config_params = config
    item.save!
    item
  end

  # Whether the report page just fetched has a row for the person.
  def page_shows?(person)
    css_select("tr[data-name]").any? { |row| row["data-name"] == person.display_name.downcase }
  end
end
