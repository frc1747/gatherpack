require "test_helper"
require_relative "../support/commitments_world"

# The commitment screens' standard layout: the page's action row, filter bar
# and folded message card, the setup page's tabs, and the forms' buttons.
class CommitmentScreensTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include CommitmentsWorld

  setup do
    travel_to Time.zone.parse("2026-10-20 12:00")
    host! "localhost"
    build_commitments_world
    @commitment = create_world_commitment
    @commitment.commitment_sources.create!(kind: "checkins", subject: @outreach)
    check_in(:member, create_world_event("Outreach Day", "2026-10-12 10:00"))
  end

  test "an organizer's footer shows Edit, Remind and More, with Delete last in More" do
    with_feature do
      sign_in person(:admin).user
      get commitment_path(@commitment)
      assert_response :success

      assert_select ".card-footer.screen-action-row" do
        assert_select "a.btn.btn-warning[href=?]", edit_commitment_path(@commitment, tab: "details"), text: "Edit"
        assert_select "button.btn.btn-primary[data-bs-toggle=collapse][data-bs-target='#message']", text: "Remind (3)"
        assert_select ".dropdown-toggle", text: "More"
        items = css_select(".dropdown-menu > li:not(.d-md-none)")
        assert_equal [ "Add an adjustment", "Duplicate", "Delete" ], items.map { |item| item.text.strip }
        assert_select items.last, "form[action=?][data-turbo-confirm=?] button.dropdown-item.text-danger",
          commitment_path(@commitment), "Delete this commitment and its adjustments?"
      end
      assert_select "a", text: "Set up", count: 0
    end
  end

  test "Remind is hidden when everyone has met the commitment" do
    [ :member, :member2, :kid ].each do |name|
      @commitment.commitment_adjustments.create!(person: person(name), credits: 2, reason: "Done")
    end
    with_feature do
      sign_in person(:admin).user
      get commitment_path(@commitment)
      assert_select ".screen-action-row button", text: /Remind/, count: 0
      assert_select ".screen-action-row a", text: "Edit"
      assert_select ".dropdown-menu li", text: "Add an adjustment"
    end
  end

  test "people who owe see no footer and no message card" do
    with_feature do
      sign_in person(:member).user
      get commitment_path(@commitment)
      assert_response :success
      assert_select ".screen-action-row", count: 0
      assert_select "#message", count: 0
    end
  end

  test "the message card starts folded, and a blank subject brings it back open with the error" do
    with_feature do
      sign_in person(:admin).user
      get commitment_path(@commitment)
      assert_select "#message.collapse:not(.show) form[action=?]", message_commitment_path(@commitment)

      assert_no_enqueued_jobs only: SendEmailJob do
        post message_commitment_path(@commitment), params: { subject: " ", body: "Please sign up." }
      end
      assert_response :unprocessable_entity
      assert_select "#message.collapse.show" do
        assert_select ".alert-danger", text: "Write a subject and a message."
        assert_select "textarea#body", text: "Please sign up."
      end
      assert_select "#progress tbody tr", 3

      assert_enqueued_jobs 3, only: SendEmailJob do
        post message_commitment_path(@commitment), params: { subject: "Shifts", body: "Please sign up." }
      end
      assert_redirected_to commitment_path(@commitment)
    end
  end

  test "the filter bar filters by team and status and holds Print" do
    sub = Team.create!(name: "Juniors", team_type: team_types(:one), parent: @members)
    Membership.create!(person: person(:member2), team: sub)
    with_feature do
      sign_in person(:admin).user
      get commitment_path(@commitment)
      assert_select ".screen-filter-bar" do
        assert_select "select#team_id option", text: "Juniors"
        assert_select "a", text: "All (3)"
        assert_select "a", text: "Not met (3)"
        assert_select ".screen-table-actions button[data-action='print#print']", text: "Print"
      end
      assert_select "#progress.table-responsive"

      get commitment_path(@commitment, team_id: sub.id)
      assert_select "#progress tbody tr", 1
      assert_select "#progress tbody tr td", text: "MemberTwo World"

      get commitment_path(@commitment, status: "met")
      assert_select "#progress tbody tr", 0
      assert_match "Nobody matches these choices.", response.body
    end
  end

  test "the setup page has tabs, and each tab saves its own part" do
    BadgeAssignment.create!(badge: @organizer_badge, person: person(:member2))
    with_feature_and_grants do
      @commitment.commitment_organizers.create!(person: person(:organizer))
      sign_in person(:organizer).user

      get edit_commitment_path(@commitment)
      assert_response :success
      assert_select ".nav-underline a.nav-link", text: /\A(Details|What counts \(1\)|Organizers \(1\))\z/, count: 3
      assert_select ".nav-underline a.active", text: "Details"
      assert_select ".card-footer a.btn.btn-secondary", text: "Cancel"
      assert_select "#sources", count: 0
      assert_select "#organizers", count: 0

      patch commitment_path(@commitment), params: { commitment: { title: "Renamed" } }
      assert_redirected_to commitment_path(@commitment)
      assert_equal "Renamed", @commitment.reload.title

      get edit_commitment_path(@commitment, tab: "sources")
      assert_select ".nav-underline a.active", text: "What counts (1)"
      assert_select "form.simple_form", count: 0
      assert_select "#sources li", text: /Check-ins at Outreach|Outreach/
      assert_select "#sources a.btn.btn-sm.btn-outline-secondary[href=?]", new_commitment_commitment_source_path(@commitment, kind: "checkins")
      post commitment_commitment_sources_path(@commitment), params: { commitment_source: { kind: "checkins", subject_id: @meeting.id, per: 1, credits: 1 } }
      assert_redirected_to edit_commitment_path(@commitment, tab: "sources")
      assert_equal 2, @commitment.commitment_sources.count

      get edit_commitment_path(@commitment, tab: "organizers")
      assert_select ".nav-underline a.active", text: "Organizers (1)"
      assert_select "#organizers input.btn.btn-sm.btn-outline-secondary[value=?]", "Add organizer"
      post commitment_commitment_organizers_path(@commitment), params: { commitment_organizer: { person_id: person(:member2).id } }
      assert_redirected_to edit_commitment_path(@commitment, tab: "organizers")
      assert_includes @commitment.reload.organizers, person(:member2)
    end
  end

  test "a details save that fails stays on the Details tab" do
    with_feature do
      sign_in person(:admin).user
      patch commitment_path(@commitment), params: { commitment: { title: "" } }
      assert_response :unprocessable_entity
      assert_select "form.simple_form input#commitment_title"
      assert_select ".nav-underline a.nav-link", text: "What counts (1)"
    end
  end

  test "the forms leave with Cancel and save with Save" do
    source = @commitment.commitment_sources.sole
    with_feature do
      sign_in person(:admin).user
      {
        new_commitment_path => commitments_path,
        new_commitment_commitment_adjustment_path(@commitment) => commitment_path(@commitment),
        new_commitment_commitment_source_path(@commitment, kind: "checkins") => edit_commitment_path(@commitment, tab: "sources"),
        edit_commitment_commitment_source_path(@commitment, source) => edit_commitment_path(@commitment, tab: "sources")
      }.each do |path, back|
        get path
        assert_response :success
        assert_select ".card-footer a.btn.btn-secondary[href=?]", back, { text: "Cancel" }, path
        assert_select ".card-footer [type=submit].btn-primary[value=Save]", { count: 1 }, path
        assert_select ".btn-warning", { count: 0 }, path
      end
    end
  end

  test "the list's table scrolls sideways" do
    with_feature do
      sign_in person(:admin).user
      get commitments_path
      assert_response :success
      assert_select "h1", text: "Commitments"
      assert_select ".table-responsive table tr##{ActionView::RecordIdentifier.dom_id(@commitment)}"
      assert_select ".card-footer a.btn-success", text: "New Commitment"
    end
  end

  test "Duplicate copies the commitment and opens the copy's Edit page" do
    with_feature do
      sign_in person(:admin).user
      get commitment_path(@commitment)
      assert_select ".dropdown-menu form[action=?] button.dropdown-item", duplicate_commitment_path(@commitment), text: "Duplicate"

      assert_difference -> { Commitment.count } => 1, -> { CommitmentSource.count } => 1 do
        post duplicate_commitment_path(@commitment)
      end
      copy = Commitment.find_by!(title: "Shifts (copy)")
      assert_redirected_to edit_commitment_path(copy, tab: "details")
      assert_equal "Duplicated. Check it, then save.", flash[:notice]
    end
  end

  test "Duplicate is refused to people who can't run commitments for the team" do
    with_feature do
      sign_in person(:member).user
      assert_no_difference -> { Commitment.count } do
        post duplicate_commitment_path(@commitment)
      end
      assert_redirected_to root_path
    end
  end

  test "the commitment tables carry the column chooser and its key" do
    with_feature do
      sign_in person(:admin).user
      get commitment_path(@commitment)
      assert_select "[data-controller~='column-chooser'][data-column-chooser-key-value='commitments-progress'] #progress table"

      get commitments_path
      assert_select ".table-responsive[data-controller~='column-chooser'][data-column-chooser-key-value='commitments-list'] table"
    end
  end
end
