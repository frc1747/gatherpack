require "application_system_test_case"
require_relative "../support/checklists_world"

class ChecklistReportTest < ApplicationSystemTestCase
  include ChecklistsWorld
  include Warden::Test::Helpers

  setup do
    # The app builds URLs for localhost; browse there so redirects stay on-host.
    Capybara.app_host = "http://localhost"
    Capybara.always_include_port = true
    build_checklists_world
    @checklist = create_world_checklist("Trip")
    add_rule(@checklist, :include, :team, team_id: @members.id)
    add_item(@checklist, :badge, "Safety", { badge_ids: [ @safety.id ] })
    give_badge(:member2, @safety)
    refresh(@checklist)
  end

  teardown do
    Capybara.app_host = nil
    Warden.test_reset!
  end

  test "the people table sorts by a heading, filters by name and ticks, and More holds the rest" do
    with_feature do
      login_as(person(:admin).user, scope: :user)
      visit checklist_path(@checklist)

      names = -> { all("tbody tr:not(.d-none) td:first-child").map(&:text) }
      assert_equal "MemberTwo World", names.call.last, "Complete sorts after the rest"

      find("th", text: "Person").click
      assert_equal names.call.sort, names.call
      find("th", text: "Person").click
      assert_equal names.call.sort.reverse, names.call

      find("input[aria-label='Filter by name']").fill_in(with: "rook")
      assert_equal [ "Rookie World" ], names.call
      find("input[aria-label='Filter by name']").fill_in(with: "")

      find("button[aria-label='Filter Safety']").click
      find("input[data-checklist-report-target=tick][data-column='2'][value=met]").check
      assert_equal [ "MemberTwo World" ], names.call

      click_on "More"
      assert_selector ".dropdown-menu.show .dropdown-item", text: "Archive"
      assert_selector ".dropdown-menu.show .dropdown-item.text-danger", text: "Delete"
    end
  end
end
