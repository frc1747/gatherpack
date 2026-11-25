require "test_helper"
require "support/orders_world"
require Rails.root.join("db/migrate/20261118150100_keep_team_managers_in_orders_roles")

# The data migration that writes "team managers always can" out as rows, so
# nothing changes on upgrade, and its undoing.
class Orders::KeepTeamManagersMigrationTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { KeepTeamManagersInOrdersRoles.new.migrate(direction) }
  end

  test "up adds a managers row to every step and line to each setting; down removes exactly those" do
    steps = [ { key: "mentor", name: "Mentor", minimum: 0, approvers: [ [ @world.approver_badge, @world.club ] ] },
      { key: "board", name: "Board", minimum: 900, approvers: [], active: false } ]
    with_orders(@world, approval_steps: steps, orders_buyers: "#{@world.buyer_badge.name} > #{@world.club.name}", orders_funding_managers: "") do
      Orders::Lists.forget_setting(:orders_funding_managers)
      buyers = Settings[:orders_buyers]

      migrate(:up)
      assert_equal %w[badge own_team_managers], ApprovalStep.find_by!(key: "mentor").approvers.map(&:kind).sort
      assert_equal %w[own_team_managers], ApprovalStep.find_by!(key: "board").approvers.map(&:kind)
      assert_equal "#{buyers}\nManagers of each team", Orders::Lists.stored_setting(:orders_buyers)
      assert_equal "Managers of each team", Orders::Lists.stored_setting(:orders_funding_managers)
      Orders::Current.reset
      assert Orders::Access.new(@world.manager).buyer_for?(@world.robotics.id)

      migrate(:up)
      assert_equal 2, ApprovalStep.find_by!(key: "mentor").approvers.count, "running again adds nothing"
      assert_equal 1, Orders::Lists.stored_setting(:orders_buyers).scan("Managers of each team").size

      migrate(:down)
      assert_equal %w[badge], ApprovalStep.find_by!(key: "mentor").approvers.map(&:kind)
      assert_empty ApprovalStep.find_by!(key: "board").approvers
      assert_equal buyers, Orders::Lists.stored_setting(:orders_buyers)
      assert_equal "", Orders::Lists.stored_setting(:orders_funding_managers)
    end
  end
end
