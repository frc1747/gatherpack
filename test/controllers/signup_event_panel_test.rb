require "test_helper"
require_relative "../support/signups_world"

# The Sign-ups panel on an event's page (spec §3.5).
class SignupEventPanelTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SignupsWorld

  setup do
    host! "localhost"
    travel_to Time.zone.parse("2026-10-11 12:00")
    build_signups_world
    @restore_settings = apply_settings(signups_organizers: "Sheet Organizer > Club")
    @sheet = create_world_sheet(created_by: person(:worker))
    @cashier = @sheet.signup_positions.create!(name: "Cashier", capacity: 4)
    @dessert = @sheet.signup_positions.create!(name: "Dessert", kind: :items, unit: "pies", capacity: 6)
    create_world_signup(@cashier, :student2)
    create_world_signup(@dessert, :student2, quantity: 2)
  end

  teardown do
    @restore_settings&.call
  end

  test "someone who can sign up sees the sheet's positions, how full they are, and names" do
    sign_in person(:student).user

    get event_path(@event)

    assert_response :success
    assert_select "#event_signups a[href=?]", signup_sheet_path(@sheet, anchor: ActionView::RecordIdentifier.dom_id(@event)), text: "Snack Stand"
    assert_select "#event_signups li", text: /Cashier\s+1 of 4 filled\s+: StudentTwo World/
    assert_select "#event_signups li", text: /Dessert\s+2 of 6 pies/
    assert_select "#event_signups a.btn", text: "Sign up"
  end

  test "names stay hidden when the sheet shows them to organizers only" do
    @sheet.names_organizers!
    sign_in person(:student).user

    get event_path(@event)
    assert_select "#event_signups li", text: /1 of 4 filled/
    assert_select "#event_signups", text: /StudentTwo World/, count: 0

    sign_in person(:worker).user
    get event_path(@event)
    assert_select "#event_signups", text: /StudentTwo World/
  end

  test "people the sheet isn't open to don't see it" do
    sign_in person(:outsider).user

    get event_path(@event)

    assert_response :success
    assert_select "#event_signups", count: 0
  end

  test "a draft shows only to its organizers, and an archived sheet to no one" do
    @sheet.draft!
    sign_in person(:student).user
    get event_path(@event)
    assert_select "#event_signups", count: 0

    sign_in person(:worker).user
    get event_path(@event)
    assert_select "#event_signups .badge", text: "Draft"
    assert_select "#event_signups a.btn", text: "Sign up", count: 0

    @sheet.archived!
    get event_path(@event)
    assert_select "#event_signups", count: 0
  end

  test "an event on no sheet has no panel" do
    other = create_world_event("Practice", Time.zone.parse("2026-10-20 18:00"))
    sign_in person(:worker).user

    get event_path(other)

    assert_response :success
    assert_select "#event_signups", count: 0
  end
end
