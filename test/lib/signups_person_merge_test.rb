require "test_helper"
require_relative "../support/signups_world"

# Runs only where feature/person-merge is present (an integration build).
class SignupsPersonMergeTest < ActiveSupport::TestCase
  include SignupsWorld

  setup do
    skip "needs feature/person-merge" unless defined?(GatherPack::PersonMerge)
    build_signups_world
  end

  test "covers the person columns of the sign-up tables" do
    { signups: %w[ person_id on_behalf_of_id signed_up_by_id ], signup_sheets: %w[ created_by_id ],
      signup_sheet_organizers: %w[ person_id ], signup_audience_rules: %w[ person_id ] }.each do |table, columns|
      columns.each { |column| assert GatherPack::PersonMerge.covers?(table, column), "#{table}.#{column}" }
    end
  end

  test "warns when both people hold a sign-up in one slot, and only then" do
    sheet = create_world_sheet(events: [ @event, create_world_event("Away Day", Time.zone.parse("2026-10-31 10:00")) ])
    cashier = sheet.signup_positions.create!(name: "Cashier", capacity: 4)
    create_world_signup(cashier, :worker)
    check = GatherPack::PersonMerge.entries.find { |e| e.table == "signups" && e.column == "person_id" }.check

    assert_nil check.call(person(:worker).id, person(:student).id)

    create_world_signup(cashier, :student)
    assert_match(/1 slot would hold both/, check.call(person(:worker).id, person(:student).id))

    create_world_signup(cashier, :student2, event: sheet.events.last)
    assert_match(/1 slot/, check.call(person(:worker).id, person(:student).id))
    assert_nil check.call(person(:worker).id, person(:student2).id)
  end

  test "a cancelled sign-up doesn't count as holding the slot" do
    cashier = create_world_sheet.signup_positions.create!(name: "Cashier", capacity: 4)
    create_world_signup(cashier, :worker)
    create_world_signup(cashier, :student, status: :cancelled)
    check = GatherPack::PersonMerge.entries.find { |e| e.table == "signups" && e.column == "person_id" }.check

    assert_nil check.call(person(:worker).id, person(:student).id)
  end
end
