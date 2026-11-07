require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/intake_world"

# decide_membership_application with registration on, decide_membership_applications and
# get_application_checklist: what the applications page, Intake::BulkDecisionsController and the
# checklist beside an application allow and show.
class Mcp::Tools::IntakeDecisionToolsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include McpWorld
  include IntakeWorld

  setup do
    host! "localhost"
    build_intake_world
    @outsider = create_intake_person("Olive", "Outsider")
    @viewers = { admin: @admin, leader: @leader, juniors_leader: @juniors_leader, outsider: @outsider }
    @applicant = create_intake_person("Riley", "Rivera", birthday: 30.years.ago.to_date)
    @application = apply(@applicant)
  end

  def apply(person, team: @juniors)
    MembershipApplication.create!(person: person, team: team, registration: @registration, source: :link)
  end

  def tool(name, viewer, **arguments)
    with_checklists { call_tool(name, user: @viewers.fetch(viewer).user, **arguments) }
  end

  def decide(viewer, application = @application, decision = "approved", **options)
    tool("decide_membership_application", viewer, membership_application_id: application.neat_id, decision: decision, **options)
  end

  def with_checklists(&block)
    with_intake({ feature_checklists: "true" }, &block)
  end

  def page_decide(viewer, application, status, **params)
    sign_in @viewers[viewer].user
    with_checklists { patch team_membership_application_path(application.team, application), params: { status: status }.merge(params) }
    sign_out @viewers[viewer].user
  end

  def checklist
    @checklist ||= begin
      list = Checklist.create!(title: "Joining", team: @northwind, status: :active, starts_on: 1.month.ago.to_date, ends_on: 1.year.from_now.to_date, created_by: @leader)
      list.checklist_rules.create!(effect: :include, target_type: :applicants, team: @juniors)
      item = list.checklist_items.new(kind: "attested", label: "Team agreement")
      item.config_params = { "statement" => "Agreement signed", "attested_by" => "guardian" }
      item.save!
      @agreement = item
      @registration.update!(checklist: list)
      list
    end
  end

  # The registration waits for its checklist (which a gate needs to exist).
  def gate_approval
    checklist
    @registration.update!(gate_approval: true)
  end

  def attest(person)
    checklist
    ChecklistAttestation.create!(person: person, key: @agreement.config["key"], statement: "Agreement signed", attested_by: person, attested_as: "guardian")
  end

  def relative_of(person, first_name)
    relative = create_intake_person(first_name, "Leader", birthday: 30.years.ago.to_date)
    sibling_of = RelationshipType.create!(parent_label: "Sibling of #{first_name}", child_label: "Sibling of #{first_name}", permission: :added_by_admin, guardianship: :none)
    Relationship.create!(parent: person, child: relative, relationship_type: sibling_of, created_by: @admin)
    relative
  end

  # decide_membership_application ---------------------------------------

  test "approving from a registration places the person, and everything added is in the call's records" do
    result = decide(:leader)

    assert_equal "approved", result.value["status"]
    assert @application.reload.approved?
    assert_equal [ @juniors, @everyone ].sort_by(&:id), @applicant.reload.teams.sort_by(&:id)
    assert_equal [ @joined_badge ], @applicant.badges.to_a
    assert_includes result.changed_records, @applicant.memberships.find_by!(team: @everyone)
    assert_includes result.changed_records, @applicant.badge_assignments.sole
    assert_equal 4, result.changed_records.size
    assert_equal @leader.id, @application.intake_placement["approved_by_id"]
  end

  test "approving gives only the badges the approver may give, as the page does" do
    admin_badge = Badge.create!(name: "Admins Only", short: "AO", color: "red", badge_type: badge_types(:one), permission: "added_by_admin")
    @registration.update!(badge_ids: [ @joined_badge.id, admin_badge.id ])
    by_page = apply(create_intake_person("Pat", "Page", birthday: 30.years.ago.to_date))

    page_decide(:leader, by_page, "approved")
    decide(:leader)

    assert_equal by_page.person.badges.to_a, @applicant.badges.to_a
    assert_equal [ @joined_badge ], @applicant.badges.to_a
  end

  test "a required pick-one team must be chosen, from the registration's list" do
    @registration.update!(pick_one_required: true)

    assert_refused("Choose a team for Riley.", Membership) { decide(:leader) }
    assert_refused("Not one of this registration's teams to pick from", Membership) { decide(:leader, pick_team_id: @mentors.neat_id) }
    assert @application.reload.pending?

    result = decide(:leader, pick_team_id: @class_2032.neat_id)
    assert_equal "approved", result.value["status"]
    assert_includes @applicant.teams, @class_2032
    assert_includes result.changed_records, @applicant.memberships.find_by!(team: @class_2032)
  end

  test "a pick is optional where it isn't required, and adds the team as the page's does" do
    by_page = apply(create_intake_person("Pat", "Page", birthday: 30.years.ago.to_date))
    page_decide(:leader, by_page, "approved", pick_team_id: @class_2031.id)
    decide(:leader, pick_team_id: @class_2031.neat_id)

    assert_equal by_page.person.teams.map(&:name).sort, @applicant.teams.map(&:name).sort
    assert_includes @applicant.teams, @class_2031
  end

  test "a pick is refused where the page would ignore it" do
    plain = MembershipApplication.create!(person: create_intake_person("Pat", "Page"), team: @juniors)

    assert_refused(/pick_team_id is for approving/, Membership) { decide(:leader, plain, pick_team_id: @class_2031.neat_id) }
    assert_refused(/pick_team_id is for approving/, Membership) { decide(:leader, @application, "denied", pick_team_id: @class_2031.neat_id) }
    assert @application.reload.pending?
  end

  test "a denial's reason is kept and sent, as the page does" do
    assert_enqueued_jobs 1, only: SendEmailJob do
      decide(:leader, @application, "denied", reason: "  We're full. ")
    end

    assert @application.reload.denied?
    assert_equal "We're full.", @application.reviewer_notes
    assert_empty @applicant.reload.teams
  end

  test "a denial without a reason says so to the applicant as the page does" do
    assert_enqueued_jobs 1, only: SendEmailJob do
      assert_equal "denied", decide(:leader, @application, "denied").value["status"]
    end
    assert_nil @application.reload.reviewer_notes
  end

  test "a reason is refused where the page would drop it" do
    plain = MembershipApplication.create!(person: create_intake_person("Pat", "Page"), team: @juniors)

    assert_refused(/A reason is kept only for a denied/, Membership) { decide(:leader, plain, "denied", reason: "No") }
    assert_refused(/A reason is kept only for a denied/, Membership) { decide(:leader, @application, "approved", reason: "No") }
    assert plain.reload.pending?
    assert @application.reload.pending?

    assert_refused(/A reason is kept only for a denied/, Membership) { call_tool("decide_membership_application", user: @leader.user, membership_application_id: @application.neat_id, decision: "denied", reason: "No") }
  end

  test "the registration's checklist holds an approval back when it gates it, with the page's words" do
    gate_approval

    assert_refused("Riley hasn't finished Joining.", Membership) { decide(:leader) }
    page_decide(:leader, @application, "approved")
    assert @application.reload.pending?
    assert_equal "Riley hasn't finished Joining.", flash[:alert]

    assert_equal "denied", decide(:leader, @application, "denied").value["status"]
  end

  test "an approval goes ahead once the checklist is done" do
    gate_approval
    attest(@applicant)
    Checklists::Refresher.new(checklist.reload).call

    assert_equal "approved", decide(:leader).value["status"]
    assert_equal "met", @application.reload.intake_placement.dig("checklist", "status")
  end

  test "nobody decides their own application or a relative's, with the tool or the page" do
    relative = relative_of(@juniors_leader, "Rae")
    application = apply(relative)

    assert_refused("You can't decide your own application or a relative's.", Membership) { decide(:juniors_leader, application) }
    page_decide(:juniors_leader, application, "approved")
    assert application.reload.pending?

    assert_equal "approved", decide(:admin, application).value["status"]
  end

  test "it allows and refuses as the page does, for each viewer and decision" do
    @viewers.each_key do |viewer|
      %w[approved denied].each do |decision|
        by_page, by_tool = 2.times.map { |i| apply(create_intake_person("P#{i}", "#{viewer}#{decision}", birthday: 30.years.ago.to_date)) }
        page_decide(viewer, by_page, decision)
        decide(viewer, by_tool, decision)

        assert_equal by_page.reload.status, by_tool.reload.status, "#{viewer} #{decision}"
      end
    end
  end

  test "with registration off it is the tool it was: no placement, no rules, and no reason to keep" do
    result = call_tool("decide_membership_application", user: @leader.user, membership_application_id: @application.neat_id, decision: "approved")

    assert_equal "approved", result.value["status"]
    assert_equal [ @juniors ], @applicant.reload.teams
    assert_equal [ result.changed_records.first, @applicant.memberships.sole ], result.changed_records
  end

  test "with registration off a reason is refused, as there is nothing to keep it" do
    assert_refused(/A reason is kept only for a denied/, Membership) do
      call_tool("decide_membership_application", user: @leader.user, membership_application_id: @application.neat_id, decision: "denied", reason: "No")
    end
    assert @application.reload.pending?
  end

  # decide_membership_applications --------------------------------------

  def bulk(viewer, applications, decision, team: @juniors, **options)
    tool("decide_membership_applications", viewer, team_id: team.neat_id, membership_application_ids: applications.map(&:neat_id), decision: decision, **options)
  end

  def page_bulk(viewer, applications, decision, team: @juniors, **params)
    sign_in @viewers[viewer].user
    with_checklists { post intake_team_bulk_decisions_path(team), params: { decision: decision, application_ids: applications.map(&:id) }.merge(params) }
    sign_out @viewers[viewer].user
  end

  test "bulk approve approves the rows it can and says why it skipped the others" do
    gate_approval
    done = create_intake_person("Dana", "Done", birthday: 30.years.ago.to_date)
    done_application = apply(done)
    attest(done)

    result = bulk(:leader, [ @application, done_application ], "approved")

    assert_equal [ done_application.neat_id ], result.value["changed"].map { |row| row["id"] }
    assert_equal [ { "id" => @application.neat_id, "reason" => "Checklist not done" } ], result.value["skipped"]
    assert done_application.reload.approved?
    assert @application.reload.pending?
    assert_includes done.teams, @everyone
    assert_includes result.changed_records, done_application
    assert_includes result.changed_records, done.memberships.find_by!(team: @everyone)
  end

  test "bulk approve skips a row that needs a pick, and one that is the manager's relative's, as the page does" do
    @registration.update!(pick_one_required: true)
    relative_application = apply(relative_of(@juniors_leader, "Rae"))

    result = bulk(:juniors_leader, [ @application, relative_application ], "approved")

    assert_empty result.value["changed"]
    assert_equal [ [ @application.neat_id, "Choose a team" ], [ relative_application.neat_id, "Yours or a relative's" ] ].sort,
      result.value["skipped"].map { |row| [ row["id"], row["reason"] ] }.sort
    assert [ @application, relative_application ].all? { |application| application.reload.pending? }
  end

  test "bulk dry_run lists what would change and changes nothing" do
    other = apply(create_intake_person("Oli", "Other", birthday: 30.years.ago.to_date))

    result = nil
    assert_no_difference([ "Membership.count", "BadgeAssignment.count" ]) { result = bulk(:leader, [ @application, other ], "approved", dry_run: true) }
    assert_equal [ @application, other ].map(&:neat_id).sort, result.value["changed"].map { |row| row["id"] }.sort
    assert result.value["dry_run"]
    assert_empty result.changed_records
    assert [ @application, other ].all? { |application| application.reload.pending? }
  end

  test "bulk deny keeps one reason on each, sends it, and goes by the page's rules for a reason" do
    other = apply(create_intake_person("Oli", "Other", birthday: 30.years.ago.to_date))
    plain = MembershipApplication.create!(person: create_intake_person("Pat", "Page", birthday: 30.years.ago.to_date), team: @juniors)

    assert_enqueued_jobs 3, only: SendEmailJob do
      result = bulk(:leader, [ @application, other, plain ], "denied", reason: "We're full.")
      assert_equal 3, result.value["changed"].size
    end
    assert [ @application, other, plain ].all? { |application| application.reload.denied? && application.reviewer_notes == "We're full." }
  end

  test "bulk skips what is already decided and what isn't yours to decide, and refuses an ID off the team" do
    @application.deny!
    other = apply(create_intake_person("Oli", "Other", birthday: 30.years.ago.to_date))
    mentor = apply(create_intake_person("Mo", "Mentor", birthday: 30.years.ago.to_date), team: @mentors)

    result = bulk(:leader, [ @application, other ], "denied")
    assert_equal [ [ @application.neat_id, "Already denied" ] ], result.value["skipped"].map { |row| [ row["id"], row["reason"] ] }
    assert_equal [ other.neat_id ], result.value["changed"].map { |row| row["id"] }

    assert_refused("Not found", Membership) { bulk(:leader, [ mentor ], "approved") }
    assert mentor.reload.pending?
  end

  test "bulk allows and refuses as the page does, for each viewer" do
    @viewers.each_key do |viewer|
      by_page, by_tool = 2.times.map { |i| apply(create_intake_person("B#{i}", viewer.to_s, birthday: 30.years.ago.to_date)) }
      page_bulk(viewer, [ by_page ], "approved")
      bulk(viewer, [ by_tool ], "approved")

      assert_equal by_page.reload.status, by_tool.reload.status, "#{viewer}"
      assert_equal %i[admin leader juniors_leader].include?(viewer), by_tool.approved?, "#{viewer}"
    end
  end

  test "bulk: a read token, writes off, a reason with approve, and the setting off" do
    assert_refused("Not allowed", Membership) { bulk(:leader, [ @application ], "approved", scopes: "mcp_read") }
    assert_refused("Writes disabled", Membership) { bulk(:leader, [ @application ], "approved", writes_enabled: false) }
    assert_refused("A reason is for denied", Membership) { bulk(:leader, [ @application ], "approved", reason: "No") }
    assert_equal "Feature off", call_tool("decide_membership_applications", user: @leader.user, team_id: @juniors.neat_id,
      membership_application_ids: [ @application.neat_id ], decision: "approved").error
    assert @application.reload.pending?
  end

  # get_application_checklist -------------------------------------------

  test "get_application_checklist gives what the page shows beside the application" do
    gate_approval
    login = checklist.checklist_items.create!(kind: "has_login", label: "Login")
    Checklists::Refresher.new(checklist.reload).call

    result = tool("get_application_checklist", :leader, membership_application_id: @application.neat_id)

    assert_equal "1 of 2 done", result.value["counts"]
    assert_equal({ "id" => checklist.neat_id, "title" => "Joining" }, result.value["checklist"])
    assert_equal [ "Team agreement" ], result.value["waiting_for"]
    assert result.value["approval_waits"]
    assert_equal [ "Team agreement", "Login" ], result.value["items"].map { |item| item["label"] }
    assert_equal [ "not_met", "met" ], result.value["items"].map { |item| item["status"] }
    assert_equal "Riley or a guardian", result.value["items"].first["to_do"]
    assert_nil result.value["items"].last["to_do"]
    assert_equal login.label, result.value["items"].last["label"]
    assert_equal @application.neat_id, result.value["application"]["id"]
  end

  test "get_application_checklist matches the page's summary" do
    checklist
    sign_in @leader.user
    with_checklists { get applications_team_path(@juniors) }
    sign_out @leader.user
    assert_select "summary", text: /1 of 1 done|0 of 1 done/

    assert_equal "0 of 1 done", tool("get_application_checklist", :leader, membership_application_id: @application.neat_id).value["counts"]
    assert_select "summary", text: /0 of 1 done/
  end

  test "get_application_checklist says approval no longer waits once it's done" do
    gate_approval
    attest(@applicant)
    Checklists::Refresher.new(checklist.reload).call

    result = tool("get_application_checklist", :leader, membership_application_id: @application.neat_id)
    assert_equal false, result.value["approval_waits"]
    assert_equal "met", result.value["overall"]["status"]
    assert_equal [], result.value["waiting_for"]
  end

  test "get_application_checklist is empty without a checklist, or one that isn't active" do
    result = tool("get_application_checklist", :leader, membership_application_id: @application.neat_id)
    assert_nil result.value["checklist"]
    assert_equal [], result.value["items"]

    checklist.update!(status: :draft)
    assert_nil tool("get_application_checklist", :leader, membership_application_id: @application.neat_id).value["checklist"]
  end

  test "get_application_checklist is for people who decide the application" do
    checklist

    with_checklists { assert_equal "Not allowed", call_tool("get_application_checklist", user: @applicant.user, membership_application_id: @application.neat_id).error }
    assert_equal "Not found", tool("get_application_checklist", :outsider, membership_application_id: @application.neat_id).error
    assert_equal "Not found", tool("get_application_checklist", :juniors_leader, membership_application_id: apply(@outsider, team: @mentors).neat_id).error
  end

  test "get_application_checklist needs registration on" do
    assert_equal "Feature off", call_tool("get_application_checklist", user: @leader.user, membership_application_id: @application.neat_id).error
  end
end
