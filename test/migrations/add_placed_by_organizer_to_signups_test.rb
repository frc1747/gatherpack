require "test_helper"
require_relative "../support/signups_world"
require Rails.root.join("db/migrate/20261105120000_add_placed_by_organizer_to_signups")

# Runs the migration down and back up inside the test's transaction.
class AddPlacedByOrganizerToSignupsTest < ActiveSupport::TestCase
  include SignupsWorld

  setup do
    build_signups_world
    cashier = create_world_sheet.signup_positions.create!(name: "Cashier")
    @signup = create_world_signup(cashier, :student, placed_by_organizer: true)
    @migration = AddPlacedByOrganizerToSignups.new
    @migration.verbose = false
  end

  teardown do
    Signup.reset_column_information
  end

  test "reverses, and rows from before it stay false" do
    @migration.migrate(:down)
    Signup.reset_column_information
    assert_not_includes Signup.column_names, "placed_by_organizer"

    @migration.migrate(:up)
    Signup.reset_column_information
    column = Signup.columns_hash.fetch("placed_by_organizer")
    assert_equal :boolean, column.type
    assert_equal false, column.null
    assert_not @signup.reload.placed_by_organizer?
  end
end
