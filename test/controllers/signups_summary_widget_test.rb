require "test_helper"
require_relative "../support/signup_credit_world"

# The "My sign-ups and commitments" summary (signups_summaries/_summary), as
# a dashboard widget whose ERB is the one line admins paste in.
class SignupsSummaryWidgetTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SignupCreditWorld

  WIDGET_ERB = '<%= render "signups_summaries/summary" %>'.freeze

  setup do
    host! "localhost"
    travel_to Time.zone.parse("2026-10-05 12:00")
    build_signup_credit_world
    @game = add_sheet_event("Game", "2026-10-10 10:00")
    @widget = Widget.create!(title: "My sign-ups and commitments", content: WIDGET_ERB, dynamic: true)
  end

  test "lists the person's upcoming active sign-ups, not past or cancelled ones" do
    past = add_sheet_event("Scrimmage", "2026-10-02 10:00")
    fair = add_sheet_event("Fair", "2026-10-12 10:00")
    sign_up(:member, @cashier, @game)
    sign_up(:member, @dish, @game)
    sign_up(:member, @cashier, past)
    sign_up(:member, @cashier, fair, status: :cancelled)

    get_body(:member)

    assert_select ".widget-body .signups-summary-signups li", 2
    assert_select ".widget-body li", text: /Cashier.*Sat Oct 10/m
    assert_select ".widget-body li", text: /Main dish/
    assert_select ".widget-body a[href=?]", signup_sheet_path(@sheet), text: "Snack Stand"
    assert_select ".widget-body a[href=?]", signup_sheets_path
    assert_no_match "Oct 2,", response.body
    assert_no_match "Oct 12", response.body
  end

  test "lists a sign-up at an event with no end time until it starts" do
    open_ended = Event.create!(name: "Open House", start_time: Time.zone.parse("2026-10-11 10:00"), end_time: nil,
      event_type: @outreach, team: @club)
    @sheet.signup_sheet_events.create!(event: open_ended)
    sign_up(:member, @cashier, open_ended)

    get_body(:member)
    assert_select ".widget-body li", text: /Cashier.*Sun Oct 11/m

    travel_to Time.zone.parse("2026-10-11 10:01")
    get_body(:member)
    assert_select ".widget-body", 0
  end

  test "shows sign-ups made for someone else, and limits the list" do
    @sheet.update!(on_behalf_of_mode: :related_people, others_relationship_type_ids: [ @parent_of.id ])
    events = (1..5).map { |day| add_sheet_event("Day #{day}", "2026-10-#{day + 10} 10:00") }
    Signup.create!(signup_slot: @cashier.signup_slots.find_by!(event: @game), person: person(:kid),
      signed_up_by: person(:organizer), on_behalf_of: person(:kid))
    events.each { |event| sign_up(:organizer, @cashier, event) }

    get_body(:organizer)

    assert_select ".widget-body .signups-summary-signups li", SignupsSummary::DEFAULT_LIMIT
    assert_select ".widget-body li", text: /Sat Oct 10.*For Kid World/m
    assert_select ".widget-body a[href=?]", signup_sheets_path, text: "All your sign-ups"
  end

  test "a parent sees their child's grouped commitment; an unrelated person doesn't" do
    commitment = create_world_commitment(group_relationship_type: @parent_of)
    commitment.commitment_sources.create!(kind: "signups", subject: @sheet)

    get_body(:organizer)

    assert_select ".widget-body .signups-summary-commitments li", 1
    assert_select ".widget-body li", text: /Shifts:\s*Kid World owes 2 more shifts/
    assert_select ".widget-body a[href=?]", person_commitments_path(person(:kid)), text: "Details"

    get_body(:crew_manager)

    assert_response :success
    assert_select ".widget-body", 0
  end

  test "the person who owes sees their own remaining and met commitments" do
    create_world_commitment
    create_world_commitment("Snacks", base_amount: 1).commitment_adjustments
      .create!(person: person(:member), credits: 1, reason: "Brought extra", created_by: person(:admin))

    get_body(:member)

    assert_select ".widget-body li", text: /Shifts:\s*You owe 2 more shifts/
    assert_select ".widget-body li", text: /Snacks:\s*You are done \(1 shift\)/
    assert_select ".widget-body a[href=?]", person_commitments_path(person(:member)), count: 2
  end

  test "renders nothing when there's nothing to show" do
    get_body(:member)

    assert_response :success
    assert_select ".widget-body", 0
  end

  test "each half hides while its feature is off, and the whole while both are" do
    sign_up(:member, @cashier, @game)
    create_world_commitment

    get_body(:member, signups: false)
    assert_select ".signups-summary-signups", 0
    assert_select ".signups-summary-commitments", 1

    get_body(:member, commitments: false)
    assert_select ".signups-summary-signups", 1
    assert_select ".signups-summary-commitments", 0

    get_body(:member, signups: false, commitments: false)
    assert_select ".widget-body", 0
  end

  test "a family's queries don't grow with its children" do
    @sheet.update!(on_behalf_of_mode: :related_people, others_relationship_type_ids: [ @parent_of.id ])
    commitment = create_world_commitment(group_relationship_type: @parent_of, additional_amount: 1)
    commitment.commitment_sources.create!(kind: "signups", subject: @sheet)
    sign_up(:organizer, @cashier, @game, on_behalf_of: :kid)

    one_child = count_queries { get_body(:organizer) }
    assert_select ".signups-summary-signups li", 1

    3.times do |index|
      child = create_world_person("Child#{index}", @members)
      Relationship.create!(parent: person(:organizer), child: child, relationship_type: @parent_of, created_by: person(:admin))
      Signup.create!(signup_slot: @dish.signup_slots.find_by!(event: @game), person: person(:organizer),
        signed_up_by: person(:organizer), on_behalf_of: child, quantity: 1)
    end

    four_children = count_queries { get_body(:organizer) }
    assert_select ".signups-summary-signups li", 4
    assert_select ".widget-body li", text: /Shifts:.*owe 5 more shifts/m
    assert_equal one_child, four_children
  end

  private

  def get_body(name, signups: true, commitments: true)
    sign_in person(name).user
    with_settings(feature_widgets: "true", feature_signups: signups.to_s, feature_commitments: commitments.to_s) do
      get body_widget_path(@widget)
    end
    assert_response :success
  end

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[ SCHEMA TRANSACTION ]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
