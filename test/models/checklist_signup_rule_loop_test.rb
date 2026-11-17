require "test_helper"
require_relative "../support/signups_world"

# A checklist rule on a position whose sign-ups, or check-ins at the
# sheet's event type or its places' events, count toward that same
# checklist.
class ChecklistSignupRuleLoopTest < ActiveSupport::TestCase
  include SignupsWorld

  # Stand-ins for the sign-up credit sources, which name a sheet or a
  # position as their subject.
  class SheetCredit < Commitments::SourceKind
    def self.label = "Sign-ups"
    def self.subject_type = "SignupSheet"
    def records(_person_ids) = []
  end

  class PositionCredit < SheetCredit
    def self.subject_type = "SignupPosition"
  end

  setup do
    travel_to Time.zone.parse("2026-10-11 12:00")
    @restore_settings = apply_settings(feature_checklists: "true")
    Commitments.register_source(:test_sheet_credit, SheetCredit)
    Commitments.register_source(:test_position_credit, PositionCredit)
    build_signups_world
    @sheet = create_world_sheet(event_type: event_types(:one))
    @position = @sheet.signup_positions.create!(name: "Float rider", capacity: 4)
    @checklist = Checklist.create!(title: "Outreach", team: @club, status: :active, starts_on: Date.new(2026, 9, 1),
      ends_on: Date.new(2099, 12, 31), created_by: person(:admin))
    @count = @checklist.checklist_items.new(kind: "count", label: "Outreach events")
    @count.config_params = { base_amount: 1, unit: "events" }
    @count.save!
    @rule = @position.signup_position_rules.create!(kind: :checklist, checklist: @checklist)
  end

  teardown do
    Commitments.unregister_source(:test_sheet_credit)
    Commitments.unregister_source(:test_position_credit)
    @restore_settings&.call
  end

  def add_source(kind, subject)
    @count.commitment.commitment_sources.create!(kind: kind, subject: subject)
  end

  test "sign-ups on the sheet counting toward the checklist warn" do
    add_source("test_sheet_credit", @sheet)

    assert_equal "Signing up here counts toward Outreach, so requiring it first means only people who already finished can sign up. " \
      "Turn on 'Also allow people partway through' or drop the rule.", Checklists::SignupRuleLoop.new(@rule).warning
  end

  test "sign-ups for the position itself counting toward the checklist warn" do
    add_source("test_position_credit", @position)

    assert Checklists::SignupRuleLoop.new(@rule).loop?
  end

  test "check-ins at the sheet's event type counting toward the checklist warn" do
    add_source("checkins", event_types(:one))

    assert Checklists::SignupRuleLoop.new(@rule).loop?
  end

  test "no warning when nothing here counts toward the checklist" do
    other_sheet = create_world_sheet("Bake Sale")
    add_source("test_sheet_credit", other_sheet)
    add_source("test_position_credit", other_sheet.signup_positions.create!(name: "Baker"))
    add_source("checkins", event_types(:two))

    assert_nil Checklists::SignupRuleLoop.new(@rule).warning
  end

  test "check-ins at the events the position has places at warn, though the sheet has no event type" do
    outreach = EventType.create!(name: "Outreach")
    parade = Event.create!(name: "Parade", start_time: Time.zone.local(2026, 12, 5, 10), end_time: Time.zone.local(2026, 12, 5, 14),
      event_type: outreach, team: @club)
    sheet = create_world_sheet("Parade", events: [ parade ])
    position = sheet.signup_positions.create!(name: "Walker", capacity: 4)
    rule = position.signup_position_rules.create!(kind: :checklist, checklist: @checklist)
    assert_nil sheet.event_type_id
    add_source("checkins", outreach)

    assert_match "Signing up here counts toward Outreach", Checklists::SignupRuleLoop.new(rule).warning
  end

  test "no warning once people partway through may take the place" do
    add_source("test_sheet_credit", @sheet)
    @rule.update!(accept_pending: true)

    assert_nil Checklists::SignupRuleLoop.new(@rule).warning
  end

  test "a source on another checklist's count doesn't warn" do
    other = Checklist.create!(title: "Robot", team: @club, status: :active, starts_on: Date.new(2026, 9, 1), created_by: person(:admin))
    item = other.checklist_items.new(kind: "count", label: "Build days")
    item.config_params = { base_amount: 1, unit: "days" }
    item.save!
    item.commitment.commitment_sources.create!(kind: "test_sheet_credit", subject: @sheet)

    assert_not Checklists::SignupRuleLoop.new(@rule).loop?
  end
end
