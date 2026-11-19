require "test_helper"
require "support/settings_test_helper"
require Rails.root.join("db/migrate/20261118120000_add_team_managers_to_inventory_managers.rb")

# The migration that writes "team managers manage their teams' inventory"
# out as a row, so upgrading changes nothing.
class Inventory::ManagersMigrationTest < ActiveSupport::TestCase
  include SettingsTestHelper

  MIGRATION = AddTeamManagersToInventoryManagers

  def stored
    Settings.instance.stored_values[:inventory_managers]
  end

  def with_stored(value)
    with_settings({}) do
      store = Settings.instance.store
      store.transaction { value.nil? ? store.delete(:inventory_managers) : store[:inventory_managers] = value }
      yield
    end
  end

  test "up appends the row to saved grants, and down takes it out again" do
    with_stored("Keeper > Club\r\nLead") do
      MIGRATION.new.up
      assert_equal "Keeper > Club\nLead\nManagers of each team", stored

      MIGRATION.new.down
      assert_equal "Keeper > Club\nLead", stored
    end
  end

  test "up writes the row when the setting is blank or not saved at all" do
    [ "", nil ].each do |value|
      with_stored(value) do
        MIGRATION.new.up
        assert_equal "Managers of each team", stored

        MIGRATION.new.down
        assert_equal "", stored
      end
    end
  end

  test "up leaves a setting that already has the row alone" do
    with_stored("managers of each team\nKeeper") do
      MIGRATION.new.up
      assert_equal "managers of each team\nKeeper", stored
    end
  end

  test "a team manager manages the same teams before and after" do
    team_type = TeamType.first || TeamType.create!(name: "Group")
    team = Team.create!(name: "Migrated #{SecureRandom.hex(3)}", team_type: team_type)
    below = Team.create!(name: "Below #{SecureRandom.hex(3)}", team_type: team_type, parent: team)
    user = User.create!(email: "lead-#{SecureRandom.hex(4)}@example.com", password: "password123")
    person = Person.create!(first_name: "Lead", last_name: "Example", display_name: "Lead Example", user: user)
    Membership.create!(person: person, team: team, manager: true)

    with_stored("") do
      assert_empty Inventory::Config.managers.team_ids(person)
      MIGRATION.new.up
      assert_equal [ team.id, below.id ].sort, Inventory::Config.managers.team_ids(person).sort
    end
  end
end
