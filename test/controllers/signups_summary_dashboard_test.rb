require "test_helper"
require_relative "../support/signup_credit_world"

# The "My Sign-ups and Commitments" card (signups_summaries/_summary) on the
# dashboard.
class SignupsSummaryDashboardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SignupCreditWorld

  setup do
    host! "localhost"
    travel_to Time.zone.parse("2026-10-05 12:00")
    build_signup_credit_world
    @game = add_sheet_event("Game", "2026-10-10 10:00")
  end

  test "lists the person's upcoming active sign-ups, not past or cancelled ones" do
    past = add_sheet_event("Scrimmage", "2026-10-02 10:00")
    fair = add_sheet_event("Fair", "2026-10-12 10:00")
    sign_up(:member, @cashier, @game)
    sign_up(:member, @dish, @game)
    sign_up(:member, @cashier, past)
    sign_up(:member, @cashier, fair, status: :cancelled)

    get_dashboard(:member)

    assert_select ".card.signups-summary h2", text: "My Sign-ups and Commitments"
    assert_select ".signups-summary .signups-summary-signups li", 2
    assert_select ".signups-summary li", text: /Cashier.*Sat Oct 10/m
    assert_select ".signups-summary li", text: /Main dish/
    assert_select ".signups-summary a[href=?]", signup_sheet_path(@sheet), text: "Snack Stand"
    assert_select ".signups-summary a[href=?]", signup_sheets_path
    assert_no_match "Oct 2,", response.body
    assert_no_match "Oct 12", response.body
  end

  test "lists a sign-up at an event with no end time until it starts" do
    open_ended = Event.create!(name: "Open House", start_time: Time.zone.parse("2026-10-11 10:00"), end_time: nil,
      event_type: @outreach, team: @club)
    @sheet.signup_sheet_events.create!(event: open_ended)
    sign_up(:member, @cashier, open_ended)

    get_dashboard(:member)
    assert_select ".signups-summary li", text: /Cashier.*Sun Oct 11/m

    travel_to Time.zone.parse("2026-10-11 10:01")
    get_dashboard(:member)
    assert_select ".signups-summary", 0
  end

  test "shows sign-ups made for someone else, and limits the list" do
    @sheet.update!(on_behalf_of_mode: :related_people, others_relationship_type_ids: [ @parent_of.id ])
    events = (1..5).map { |day| add_sheet_event("Day #{day}", "2026-10-#{day + 10} 10:00") }
    Signup.create!(signup_slot: @cashier.signup_slots.find_by!(event: @game), person: person(:kid),
      signed_up_by: person(:organizer), on_behalf_of: person(:kid))
    events.each { |event| sign_up(:organizer, @cashier, event) }

    get_dashboard(:organizer)

    assert_select ".signups-summary .signups-summary-signups li", SignupsSummary::DEFAULT_LIMIT
    assert_select ".signups-summary li", text: /Sat Oct 10.*For Kid World/m
    assert_select ".signups-summary a[href=?]", signup_sheets_path, text: "All your sign-ups"
  end

  test "leaves out sign-ups on sheets the person may not see" do
    draft = SignupSheet.create!(title: "Draft Stand", team: @club, status: :draft, created_by: person(:organizer))
    greeter = draft.signup_positions.create!(name: "Greeter", kind: :people, capacity: 2)
    draft.signup_sheet_events.create!(event: @game)
    Signup.create!(signup_slot: greeter.signup_slots.find_by!(event: @game), person: person(:member), signed_up_by: person(:organizer))
    sign_up(:member, @cashier, @game)

    get_dashboard(:member)

    assert_select ".signups-summary .signups-summary-signups li", 1
    assert_select ".signups-summary li", text: /Cashier/
    assert_no_match "Draft Stand", response.body
    assert_no_match "Greeter", response.body
  end

  test "a parent sees their child's grouped commitment; an unrelated person doesn't" do
    commitment = create_world_commitment(group_relationship_type: @parent_of)
    commitment.commitment_sources.create!(kind: "signups", subject: @sheet)

    get_dashboard(:organizer)

    assert_select ".signups-summary .signups-summary-commitments li", 1
    assert_select ".signups-summary li", text: /Shifts:\s*Kid World owes 2 more shifts/
    assert_select ".signups-summary a[href=?]", person_commitments_path(person(:kid)), text: "Details"

    get_dashboard(:crew_manager)

    assert_response :success
    assert_select ".signups-summary", 0
  end

  test "the person who owes sees their own remaining and met commitments" do
    create_world_commitment
    create_world_commitment("Snacks", base_amount: 1).commitment_adjustments
      .create!(person: person(:member), credits: 1, reason: "Brought extra", created_by: person(:admin))

    get_dashboard(:member)

    assert_select ".signups-summary li", text: /Shifts:\s*You owe 2 more shifts/
    assert_select ".signups-summary li", text: /Snacks:\s*You are done \(1 shift\)/
    assert_select ".signups-summary a[href=?]", person_commitments_path(person(:member)), count: 2
  end

  test "renders nothing when there's nothing to show" do
    get_dashboard(:member)

    assert_response :success
    assert_select ".signups-summary", 0
  end

  test "each half hides while its feature is off, and the whole while both are" do
    sign_up(:member, @cashier, @game)
    create_world_commitment

    get_dashboard(:member, signups: false)
    assert_select ".signups-summary-signups", 0
    assert_select ".signups-summary-commitments", 1

    get_dashboard(:member, commitments: false)
    assert_select ".signups-summary-signups", 1
    assert_select ".signups-summary-commitments", 0

    get_dashboard(:member, signups: false, commitments: false)
    assert_select ".signups-summary", 0
  end

  test "a family's queries don't grow with its children" do
    @sheet.update!(on_behalf_of_mode: :related_people, others_relationship_type_ids: [ @parent_of.id ])
    commitment = create_world_commitment(group_relationship_type: @parent_of, additional_amount: 1)
    commitment.commitment_sources.create!(kind: "signups", subject: @sheet)
    sign_up(:organizer, @cashier, @game, on_behalf_of: :kid)

    one_child = count_queries { get_dashboard(:organizer) }
    assert_select ".signups-summary-signups li", 1

    3.times do |index|
      child = create_world_person("Child#{index}", @members)
      Relationship.create!(parent: person(:organizer), child: child, relationship_type: @parent_of, created_by: person(:admin))
      Signup.create!(signup_slot: @dish.signup_slots.find_by!(event: @game), person: person(:organizer),
        signed_up_by: person(:organizer), on_behalf_of: child, quantity: 1)
    end

    four_children = count_queries { get_dashboard(:organizer) }
    assert_select ".signups-summary-signups li", 4
    assert_select ".signups-summary li", text: /Shifts:.*owe 5 more shifts/m
    assert_equal one_child, four_children
  end

  private

  def get_dashboard(name, signups: true, commitments: true)
    sign_in person(name).user
    with_settings(feature_signups: signups.to_s, feature_commitments: commitments.to_s) do
      get root_path
    end
    assert_response :success
  end

  # Queries made while the summary card renders, so the rest of the
  # dashboard's page doesn't count. Query cache hits count too: whether a
  # preload hits the cache depends on the order of its ids.
  def count_queries(&block)
    count = 0
    rendering = false
    partial = Class.new do
      define_method(:start) { |_name, _id, payload| rendering = true if payload[:identifier].to_s.end_with?("signups_summaries/_summary.html.erb") }
      define_method(:finish) { |_name, _id, payload| rendering = false if payload[:identifier].to_s.end_with?("signups_summaries/_summary.html.erb") }
    end.new
    counter = ->(*, payload) { count += 1 if rendering && !payload[:name].in?(%w[ SCHEMA TRANSACTION ]) }
    ActiveSupport::Notifications.subscribed(partial, "render_partial.action_view") do
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    end
    assert_operator count, :>, 0
    count
  end
end
