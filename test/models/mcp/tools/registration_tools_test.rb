require "test_helper"
require_relative "../../../support/mcp_world"
require_relative "../../../support/intake_world"

# list_registrations, get_registration, set_registration_state and copy_registration:
# what Intake::RegistrationsController's index, show, close, update and copy/create allow.
class Mcp::Tools::RegistrationToolsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpWorld
  include IntakeWorld

  setup do
    host! "localhost"
    build_intake_world
    @outsider = create_intake_person("Olive", "Outsider")
    @juniors_registration = Intake::Registration.create!(team: @juniors, title: "Join Juniors", opens_at: 2.days.ago, closes_at: 10.days.from_now,
      created_by: @juniors_leader, apply_team_ids: [ @juniors.id ])
    @viewers = { admin: @admin, leader: @leader, juniors_leader: @juniors_leader, outsider: @outsider }
  end

  def tool(name, viewer, **arguments)
    with_intake { call_tool(name, user: @viewers.fetch(viewer).user, **arguments) }
  end

  test "it needs registration on" do
    result = call_tool("list_registrations", user: @leader.user)
    assert_equal "Feature off", result.error
  end

  test "list_registrations lists what the viewer runs, newest opening first, and refuses a member" do
    result = tool("list_registrations", :admin)
    assert_equal [ @registration.neat_id, @juniors_registration.neat_id ], result.value["items"].map { |item| item["id"] }

    item = result.value["items"].first
    assert_equal({ "id" => @northwind.neat_id, "name" => "Northwind" }, item["team"])
    assert_equal "open", item["status"]
    assert_equal false, item["kiosk"]

    assert_equal [ @registration.neat_id ], tool("list_registrations", :leader, team_id: @northwind.neat_id).value["items"].map { |row| row["id"] }
    assert_equal [ @juniors_registration.neat_id ], tool("list_registrations", :juniors_leader).value["items"].map { |row| row["id"] }
    assert_equal "Not allowed", tool("list_registrations", :outsider).error
  end

  test "list_registrations leaves out archived ones unless asked, and says closed and not open yet" do
    @registration.update_columns(opens_at: 40.days.ago, closes_at: 30.days.ago)
    @juniors_registration.update_columns(opens_at: 1.day.from_now, closes_at: nil)

    with_settings(intake_archive_days: "10") do
      assert_equal [ @juniors_registration.neat_id ], tool("list_registrations", :admin).value["items"].map { |row| row["id"] }
      all = tool("list_registrations", :admin, archived: true).value["items"]
      assert_equal [ "not open yet", "closed" ], all.map { |row| row["status"] }
      assert_nil all.first["closes_at"]
    end
  end

  test "list_registrations shows what the page lists" do
    sign_in @juniors_leader.user
    with_intake { get intake_registrations_path }
    assert_match "Join Juniors", response.body
    assert_no_match "Join Northwind", response.body
    sign_out @juniors_leader.user
  end

  test "get_registration shows the page's details and counts" do
    MembershipApplication.create!(person: create_intake_person("Riley", "Rivera"), team: @juniors, registration: @registration, source: :link)
    result = tool("get_registration", :leader, registration_id: @registration.neat_id).value

    assert_equal "Join Northwind", result["title"]
    assert_equal @registration.slug, result["slug"]
    assert_equal %w[Juniors Mentors Volunteers], result["apply_teams"].map { |team| team["name"] }.sort
    assert_equal [ "Everyone" ], result["also_add_teams"].map { |team| team["name"] }
    assert_equal [ "Joined Online" ], result["also_give_badges"].map { |badge| badge["name"] }
    assert_equal [ "Class of 2031", "Class of 2032" ], result["pick_one_teams"].map { |team| team["name"] }
    assert_equal [ "Families" ], result["guardian_also_add_teams"].map { |team| team["name"] }
    assert_equal({ "pending" => 1, "approved" => 0, "denied" => 0 }, result["applications"])
    assert_nil result["checklist"]
  end

  test "get_registration gives the join path only for self-service, and no keys" do
    @registration.update!(self_service: false)
    assert_nil tool("get_registration", :leader, registration_id: @registration.neat_id).value["join_path"]

    @registration.update!(self_service: true)
    result = tool("get_registration", :leader, registration_id: @registration.neat_id)

    assert_equal "/join/#{@registration.slug}", result.value["join_path"]
    assert_no_match(/turnstile|secret/i, result.value.to_json)
  end

  test "get_registration names the checklist, and says when it does nothing" do
    checklist = Checklist.create!(title: "Joining", team: @northwind, status: :draft, created_by: @leader)
    @registration.update!(checklist: checklist)
    with_settings(feature_checklists: "true") do
      result = tool("get_registration", :leader, registration_id: @registration.neat_id).value
      assert_equal({ "id" => checklist.neat_id, "title" => "Joining", "active" => false, "uncovered_teams" => [] }, result["checklist"])
    end
  end

  test "get_registration allows and refuses as the page's show does" do
    @viewers.each_key do |viewer|
      sign_in @viewers[viewer].user
      with_intake { get intake_registration_path(@registration) }
      page = response.successful?
      sign_out @viewers[viewer].user

      result = tool("get_registration", viewer, registration_id: @registration.neat_id)
      assert_equal page, !result.error?, "#{viewer}"
    end
  end

  test "get_registration: one you can't run is not found" do
    assert_equal "Not found", tool("get_registration", :juniors_leader, registration_id: @registration.neat_id).error
    assert_equal "Not found", tool("get_registration", :admin, registration_id: @northwind.neat_id).error
  end

  test "set_registration_state closes now, as Close now does, and leaves a closed one alone" do
    travel_to Time.current.change(usec: 0) do
      result = tool("set_registration_state", :leader, registration_id: @registration.neat_id, state: "close")

      assert_equal "closed", result.value["status"]
      assert_equal Time.current, @registration.reload.closes_at
      assert_equal [ @registration ], result.changed_records

      @registration.update_columns(closes_at: 1.day.ago)
      tool("set_registration_state", :leader, registration_id: @registration.neat_id, state: "close")
      assert_equal 1.day.ago, @registration.reload.closes_at
    end
  end

  test "set_registration_state opens one that hasn't opened, and reopens a closed one" do
    closes = 5.days.from_now
    @registration.update_columns(opens_at: 2.days.from_now, closes_at: closes)
    travel_to Time.current.change(usec: 0) do
      assert_equal "open", tool("set_registration_state", :leader, registration_id: @registration.neat_id, state: "open").value["status"]
      assert_equal Time.current, @registration.reload.opens_at
      assert_in_delta closes, @registration.closes_at, 0.01
    end

    @registration.update_columns(closes_at: 1.hour.ago)
    result = tool("set_registration_state", :leader, registration_id: @registration.neat_id, state: "open")
    assert_equal "open", result.value["status"]
    assert_nil @registration.reload.closes_at

    @registration.update_columns(closes_at: 1.hour.ago)
    tool("set_registration_state", :leader, registration_id: @registration.neat_id, state: "open", closes_at: 3.days.from_now.iso8601)
    assert_in_delta 3.days.from_now, @registration.reload.closes_at, 2
  end

  test "set_registration_state refuses a bad end date and an end given with close" do
    assert_match(/closes_at must be an ISO 8601/, tool("set_registration_state", :leader, registration_id: @registration.neat_id, state: "open", closes_at: "soon").error)
    assert_match(/closes_at is for open/, tool("set_registration_state", :leader, registration_id: @registration.neat_id, state: "close", closes_at: "2030-01-01T00:00:00").error)

    closed_at = 1.hour.ago
    @registration.update_columns(closes_at: closed_at)
    result = tool("set_registration_state", :leader, registration_id: @registration.neat_id, state: "open", closes_at: 1.day.ago.iso8601)
    assert_match(/must be after it opens/, result.error)
    assert_equal closed_at.to_i, @registration.reload.closes_at.to_i
  end

  test "set_registration_state closes and opens as the page's close and update allow" do
    @viewers.each_key do |viewer|
      sign_in @viewers[viewer].user
      with_intake { patch close_intake_registration_path(@registration) }
      page = @registration.reload.closed?
      sign_out @viewers[viewer].user
      @registration.update_columns(closes_at: 30.days.from_now)

      result = tool("set_registration_state", viewer, registration_id: @registration.neat_id, state: "close")
      assert_equal page, @registration.reload.closed?, "#{viewer} closing"
      assert_equal page, !result.error?, "#{viewer} closing"
      @registration.update_columns(closes_at: 30.days.from_now)
    end
  end

  test "set_registration_state: a read token, writes off, and a registration you can't see" do
    assert_equal "Not allowed", tool("set_registration_state", :leader, registration_id: @registration.neat_id, state: "close", scopes: "mcp_read").error
    assert_equal "Writes disabled", tool("set_registration_state", :leader, registration_id: @registration.neat_id, state: "close", writes_enabled: false).error
    assert_equal "Not found", tool("set_registration_state", :juniors_leader, registration_id: @registration.neat_id, state: "close").error
    assert_equal "Not found", tool("set_registration_state", :outsider, registration_id: @registration.neat_id, state: "close").error
    assert @registration.reload.open?
  end

  test "copy_registration makes a new one with the dates given, as Copy then save does" do
    opens = 40.days.from_now.change(usec: 0)
    result = nil
    assert_difference("Intake::Registration.count", 1) do
      result = tool("copy_registration", :leader, registration_id: @registration.neat_id, opens_at: opens.iso8601)
    end

    copy = registration_from(result.value["id"])
    assert_equal @registration.title, copy.title
    assert_equal opens, copy.opens_at
    assert_in_delta opens + (@registration.closes_at - @registration.opens_at), copy.closes_at, 0.01
    assert_not_equal @registration.slug, copy.slug
    assert_equal @leader, copy.created_by
    assert_nil copy.successor
    %i[apply also_add pick_one guardian_also_add].each { |kind| assert_equal @registration.public_send(:"#{kind}_team_ids").sort, copy.public_send(:"#{kind}_team_ids").sort }
    assert_equal @registration.badge_ids, copy.badge_ids
    assert_equal [ copy ], result.changed_records
    assert_equal "not open yet", result.value["status"]
  end

  test "copy_registration takes closes_at and title, and keeps no end for one without" do
    @registration.update!(closes_at: nil)
    opens = 3.days.from_now.change(usec: 0)
    result = tool("copy_registration", :leader, registration_id: @registration.neat_id, opens_at: opens.iso8601, title: "Next time")
    assert_equal "Next time", result.value["title"]
    assert_nil result.value["closes_at"]

    closes = 9.days.from_now.change(usec: 0)
    result = tool("copy_registration", :leader, registration_id: @registration.neat_id, opens_at: opens.iso8601, closes_at: closes.iso8601)
    assert_equal closes.iso8601, Time.zone.parse(result.value["closes_at"]).iso8601
    assert_match(/closes_at must be/, tool("copy_registration", :leader, registration_id: @registration.neat_id, opens_at: opens.iso8601, closes_at: "x").error)
    assert_match(/must be after it opens/, tool("copy_registration", :leader, registration_id: @registration.neat_id, opens_at: opens.iso8601, closes_at: 1.day.from_now.iso8601).error)
  end

  test "copy_registration carries over only the teams and badges the copier may, as the page's save does" do
    admin_badge = Badge.create!(name: "Admins Only", short: "AO", color: "red", badge_type: badge_types(:one), permission: "added_by_admin")
    # A badge of the team Juniors' leader manages, so theirs to give.
    juniors_badge = Badge.create!(name: "Joined Juniors", short: "JJ", color: "blue", badge_type: badge_types(:one), team: @juniors,
      permission: "added_by_manager")
    @registration.update!(also_add_team_ids: [ @everyone.id, @juniors.id ], badge_ids: [ juniors_badge.id, admin_badge.id ])
    @juniors_registration.update!(also_add_team_ids: [ @everyone.id, @juniors.id ], badge_ids: [ juniors_badge.id, admin_badge.id ])

    result = tool("copy_registration", :juniors_leader, registration_id: @juniors_registration.neat_id, opens_at: 5.days.from_now.iso8601)
    copy = registration_from(result.value["id"])

    assert_equal [ @juniors.id ], copy.also_add_team_ids
    assert_equal [ @juniors.id ], copy.apply_team_ids
    assert_equal [ juniors_badge.id ], copy.badge_ids

    sign_in @juniors_leader.user
    with_intake { get copy_intake_registration_path(@juniors_registration) }
    assert_response :success
  end

  test "copy_registration is refused where the copy would be invalid, or the viewer can't copy" do
    @juniors_registration.update!(gate_approval: false)
    # Juniors' leader manages only Juniors: a Northwind copy would have no team to apply to.
    assert_equal "Not found", tool("copy_registration", :juniors_leader, registration_id: @registration.neat_id, opens_at: 5.days.from_now.iso8601).error
    assert_equal "Not found", tool("copy_registration", :outsider, registration_id: @registration.neat_id, opens_at: 5.days.from_now.iso8601).error
    assert_equal "Writes disabled", tool("copy_registration", :leader, registration_id: @registration.neat_id, opens_at: 5.days.from_now.iso8601, writes_enabled: false).error
    assert_equal 2, Intake::Registration.count
  end

  test "copy_registration with checklists on drops a checklist the copier doesn't run, and so a gate with none is refused" do
    checklist = Checklist.create!(title: "Joining", team: @northwind, status: :active, created_by: @leader)
    @juniors_registration.update!(checklist: checklist, gate_approval: true)

    with_settings(feature_checklists: "true") do
      result = tool("copy_registration", :juniors_leader, registration_id: @juniors_registration.neat_id, opens_at: 5.days.from_now.iso8601)
      assert_match(/needs a checklist/, result.error)

      @juniors_registration.update!(gate_approval: false)
      result = tool("copy_registration", :juniors_leader, registration_id: @juniors_registration.neat_id, opens_at: 5.days.from_now.iso8601)
      assert_nil registration_from(result.value["id"]).checklist_id

      result = tool("copy_registration", :leader, registration_id: @juniors_registration.neat_id, opens_at: 5.days.from_now.iso8601)
      assert_equal checklist.id, registration_from(result.value["id"]).checklist_id
    end
  end

  test "copy_registration with checklists off copies no checklist and no gate, whoever runs it, as the page's form does" do
    checklist = Checklist.create!(title: "Joining", team: @northwind, status: :active, created_by: @leader)
    @juniors_registration.update!(checklist: checklist, gate_approval: true)

    [ :juniors_leader, :leader ].each do |viewer|
      copy = registration_from(tool("copy_registration", viewer, registration_id: @juniors_registration.neat_id, opens_at: 5.days.from_now.iso8601).value["id"])
      assert_nil copy.checklist_id, viewer.to_s
      assert_not copy.gate_approval?, viewer.to_s
    end
  end

  private

  def registration_from(neat_id)
    Mcp.find_by_neat_id(Intake::Registration, neat_id)
  end
end
