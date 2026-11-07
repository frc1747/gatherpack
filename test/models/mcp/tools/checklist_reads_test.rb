require "test_helper"
require_relative "../../../support/mcp_checklists_world"

class Mcp::Tools::ChecklistReadsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include McpChecklistsWorld

  setup do
    host! "localhost"
    build_mcp_world
    build_mcp_checklists_world
  end

  VIEWERS = %i[alpha_member kid_parent crew_lead grant_holder organizer alpha_manager admin beta_member].freeze

  def report(viewer, **arguments)
    call_tool("checklist_results", user: user(viewer), checklist_id: @checklist.neat_id, limit: 100, **arguments)
  end

  # { person ID => row } of the report the viewer is given.
  def rows(viewer, **arguments)
    result = report(viewer, **arguments)
    assert_nil result.error, viewer
    result.value["rows"].to_h { |row| [ row["person"]["id"], row ] }
  end

  test "list_checklists lists what the checklists page lists, by title, and hides archived ones" do
    other = Checklist.create!(title: "Aardvark", team: @beta, status: :active, starts_on: Date.current, created_by: person(:admin))
    archived = Checklist.create!(title: "Old", team: @alpha, status: :archived, starts_on: 2.years.ago.to_date, created_by: person(:admin))
    draft = Checklist.create!(title: "Draft", team: @alpha, status: :draft, starts_on: Date.current, created_by: person(:admin))

    VIEWERS.each do |viewer|
      sign_in user(viewer)
      get checklists_path
      on_page = [ other, @checklist, archived, draft ].select { |checklist| response.body.include?(checklist.title) && response.body.include?(checklist_path(checklist)) }
      sign_out user(viewer)

      result = call_tool("list_checklists", user: user(viewer), include_archived: true)
      listed = result.value["items"].map { |item| item["id"] }
      assert_equal on_page.reject(&:archived?).map(&:neat_id).sort, call_tool("list_checklists", user: user(viewer)).value["items"].map { |item| item["id"] }.sort, viewer
      assert_equal (on_page.map(&:neat_id) - [ archived.neat_id ] + (listed & [ archived.neat_id ])).sort, listed.sort, viewer
    end

    result = call_tool("list_checklists", user: user(:admin))
    assert_equal %w[Aardvark Draft Eligibility], result.value["items"].map { |item| item["title"] }
    assert_equal [ true, true, true ], result.value["items"].map { |item| item["organizer"] }
    assert_equal [ false ], call_tool("list_checklists", user: user(:alpha_member)).value["items"].map { |item| item["organizer"] }.uniq
    assert_equal [ "Old" ], call_tool("list_checklists", user: user(:admin), include_archived: true).value["items"].map { |item| item["title"] } - %w[Aardvark Draft Eligibility]
    assert_equal [ @checklist.neat_id ], call_tool("list_checklists", user: user(:grant_holder)).value["items"].map { |item| item["id"] }
    assert_empty call_tool("list_checklists", user: user(:beta_member)).value["items"]
    assert_equal({ "items" => 1, "truncated" => true }, call_tool("list_checklists", user: user(:admin), limit: 1).value.then { |v| { "items" => v["items"].size, "truncated" => v["truncated"] } })
  end

  test "checklist_results shows each viewer the same people the report page shows" do
    VIEWERS.each do |viewer|
      sign_in user(viewer)
      get checklist_path(@checklist)
      page_status = response.status
      people = @people.values.reject { |person| person == self.person(viewer) }.select { |person| page_status == 200 && page_shows?(person) }
      sign_out user(viewer)

      if page_status == 404
        assert_equal "Not found", report(viewer).error, viewer
      else
        assert_equal 200, page_status, viewer
        shown = rows(viewer).keys.map { |id| @people.values.find { |person| person.neat_id == id } }.compact
        assert_equal people.map(&:neat_id).sort, (shown - [ person(viewer) ]).map(&:neat_id).sort, viewer
      end
    end
  end

  test "who sees what: the subject, their guardian, a leader, a grant holder, an organizer and a stranger" do
    subject = person(:alpha_member).neat_id
    kid = person(:kid).neat_id

    assert_equal [ subject ], rows(:alpha_member).keys
    assert_includes rows(:kid_parent), kid
    assert_not_includes rows(:kid_parent), subject
    assert_includes rows(:crew_lead), subject
    assert_not_includes rows(:crew_lead), kid, "the leader of Crew doesn't lead Alpha's other members"
    assert_includes rows(:grant_holder), subject
    assert_includes rows(:grant_holder), kid
    assert_equal "Not found", report(:beta_member).error
    [ :organizer, :alpha_manager, :admin ].each { |viewer| assert_includes rows(viewer), kid, viewer }

    count_cell = ->(viewer) { rows(viewer).fetch(subject)["items"].find { |cell| cell["item"]["label"] == "Shifts" } }
    assert_equal({ "confirmed" => 1, "owed" => 2, "planned" => 0, "remaining" => 1 }, count_cell.call(:organizer)["measures"].slice("confirmed", "owed", "planned", "remaining"))
    assert_equal 1, count_cell.call(:alpha_member)["measures"]["confirmed"]
    assert_equal 1, count_cell.call(:crew_lead)["measures"]["confirmed"]
    assert_equal "full", count_cell.call(:grant_holder)["access"]
  end

  test "a guardian doesn't see a count item that isn't theirs to see, as the page doesn't" do
    kid_row = rows(:kid_parent).fetch(person(:kid).neat_id)
    assert_equal [ "Login", "Handbook", "Safety" ].sort, kid_row["items"].map { |cell| cell["item"]["label"] }.sort
    assert_not_includes kid_row["items"].map { |cell| cell["item"]["label"] }, "Shifts"
  end

  test "checklist_results limits rows, puts the viewer's family first and ignores as_of for those who don't run it" do
    result = call_tool("checklist_results", user: user(:alpha_manager), checklist_id: @checklist.neat_id, limit: 2)
    assert_equal [ 2, true ], [ result.value["rows"].size, result.value["truncated"] ]
    assert_equal [ person(:kid).neat_id ], report(:kid_parent).value["rows"].select { |row| row["family"] }.map { |row| row["person"]["id"] }

    as_of = (Date.current - 1.month).iso8601
    assert_nil report(:alpha_manager, as_of: as_of).error
    assert_equal "as_of must be a date, YYYY-MM-DD", report(:alpha_manager, as_of: "2026-13-45").error
    assert_nil report(:alpha_member, as_of: as_of).error, "ignored for someone who doesn't run it, as the page ignores it"
  end

  test "a draft is for those who run it" do
    draft = Checklist.create!(title: "Draft", team: @alpha, status: :draft, starts_on: Date.current, created_by: person(:admin))
    draft.checklist_rules.create!(effect: :include, target_type: :team, team: @alpha)

    assert_nil call_tool("checklist_results", user: user(:alpha_manager), checklist_id: draft.neat_id).error
    assert_equal "Not found", call_tool("checklist_results", user: user(:alpha_member), checklist_id: draft.neat_id).error
    assert_equal "Not found", call_tool("checklist_status", user: user(:alpha_member), checklist_id: draft.neat_id).error
  end

  test "checklist_status gives the person's results on one checklist or every one that covers them" do
    result = call_tool("checklist_status", user: user(:alpha_member))
    entry = result.value["checklists"].sole
    assert_equal [ person(:alpha_member).neat_id, @checklist.neat_id ], [ result.value["person"]["id"], entry["checklist"]["id"] ]
    assert_equal %w[Login Shifts Handbook Safety], entry["items"].map { |cell| cell["item"]["label"] }
    assert_equal "not_met", entry["overall"]["status"]
    assert_equal "I confirm", entry["items"].find { |cell| cell["item"]["label"] == "Handbook" }["fix"]["label"]

    one = call_tool("checklist_status", user: user(:alpha_manager), person_id: person(:alpha_member).neat_id, checklist_id: @checklist.neat_id)
    assert_equal entry["items"].map { |cell| cell["status"] }, one.value["checklists"].sole["items"].map { |cell| cell["status"] }
  end

  test "checklist_status refuses people the viewer can't see, the way the page does" do
    sign_in user(:beta_member)
    get person_checklists_path(person(:alpha_member))
    assert_response :not_found
    sign_out user(:beta_member)
    assert_equal "Not found", call_tool("checklist_status", user: user(:beta_member), person_id: person(:alpha_member).neat_id).error
    assert_equal "Not found", call_tool("checklist_status", user: user(:beta_member), person_id: person(:alpha_member).neat_id, checklist_id: @checklist.neat_id).error
    assert_equal "Not found", call_tool("checklist_status", user: user(:alpha_member), person_id: person(:kid).neat_id, checklist_id: @checklist.neat_id).error
    assert_equal "Not found", call_tool("checklist_status", user: user(:alpha_member), person_id: "per_nope").error
    assert_equal "Not found", call_tool("checklist_status", user: user(:alpha_member), checklist_id: "chkl_nope").error
    assert_equal [ person(:kid).neat_id ], call_tool("checklist_status", user: user(:kid_parent), person_id: person(:kid).neat_id).value["checklists"].map { |entry| entry["overall"] && person(:kid).neat_id }
  end

  test "people_meeting matches the report's overall column within the viewer's rows" do
    all = rows(:alpha_manager).transform_values { |row| row["overall"]["status"] }
    { "met" => "met", "not_met" => "not_met" }.each do |status, expected|
      ids = call_tool("people_meeting", user: user(:alpha_manager), checklist_id: @checklist.neat_id, status: status, limit: 100).value["people"].map { |entry| entry["person"]["id"] }
      assert_equal all.select { |_, overall| overall == expected }.keys.sort, ids.sort, status
    end
    not_done = call_tool("people_meeting", user: user(:alpha_manager), checklist_id: @checklist.neat_id, status: "not_done", limit: 100).value
    assert_equal all.count { |_, overall| overall != "met" }, not_done["total"]

    # Someone who sees only their own row learns only about it.
    own = call_tool("people_meeting", user: user(:alpha_member), checklist_id: @checklist.neat_id, status: "not_done").value
    assert_equal [ person(:alpha_member).neat_id ], own["people"].map { |entry| entry["person"]["id"] }
    assert_equal "Not found", call_tool("people_meeting", user: user(:beta_member), checklist_id: @checklist.neat_id).error
    assert_equal 1, call_tool("people_meeting", user: user(:alpha_manager), checklist_id: @checklist.neat_id, status: "not_done", limit: 1).value["people"].size
  end
end
