require "test_helper"

class LedgersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    # Robotics (run by @manager)
    # └── Robotics Jr
    # Drama (unrelated)
    @robotics = Team.create!(name: "Robotics", team_type: team_types(:one))
    @robotics_jr = Team.create!(name: "Robotics Jr", team_type: team_types(:one), parent: @robotics)
    @drama = Team.create!(name: "Drama", team_type: team_types(:one))

    @admin_user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin_user, first_name: "Ada", last_name: "Admin")

    @manager_user = User.create!(email: "manager@example.com", password: "Password1!")
    @manager = Person.create!(user: @manager_user, first_name: "Mary", last_name: "Manager")
    Membership.create!(person: @manager, team: @robotics, manager: true)

    @ledger = Ledger.create!(name: "Robotics fund", team: @robotics)
  end

  # --- create -------------------------------------------------------------

  test "a manager cannot create a ledger on a team they don't manage" do
    sign_in @manager_user

    post ledgers_path, params: { ledger: { name: "Drama fund", team_id: @drama.id } }

    assert_not Ledger.exists?(name: "Drama fund"), "manager of Robotics created a ledger on the Drama team"
    assert_redirected_to root_path
  end

  test "a manager can create a ledger on their team and its sub-teams" do
    sign_in @manager_user

    [ @robotics, @robotics_jr ].each do |team|
      post ledgers_path, params: { ledger: { name: "#{team.name} kitty", team_id: team.id } }

      assert_redirected_to ledger_path(Ledger.find_by!(name: "#{team.name} kitty", team: team))
    end
  end

  test "an admin can create a ledger on any team" do
    sign_in @admin_user

    post ledgers_path, params: { ledger: { name: "Drama fund", team_id: @drama.id } }

    assert_redirected_to ledger_path(Ledger.find_by!(name: "Drama fund", team: @drama))
  end

  # --- update -------------------------------------------------------------

  test "a manager cannot move their ledger to a team they don't manage" do
    sign_in @manager_user

    patch ledger_path(@ledger), params: { ledger: { team_id: @drama.id } }

    assert_equal @robotics, @ledger.reload.team, "manager of Robotics moved a ledger to the Drama team"
    assert_redirected_to root_path
  end

  test "a manager can rename their ledger and move it to a sub-team" do
    sign_in @manager_user

    patch ledger_path(@ledger), params: { ledger: { name: "Robotics Jr fund", team_id: @robotics_jr.id } }

    assert_redirected_to ledger_path(@ledger)
    assert_equal "Robotics Jr fund", @ledger.reload.name
    assert_equal @robotics_jr, @ledger.team
  end

  test "an admin can move a ledger to any team" do
    sign_in @admin_user

    patch ledger_path(@ledger), params: { ledger: { team_id: @drama.id } }

    assert_redirected_to ledger_path(@ledger)
    assert_equal @drama, @ledger.reload.team
  end
end
