require "test_helper"
require "support/orders_world"
require Rails.root.join("db/migrate/20261117100200_create_approval_steps")
require Rails.root.join("db/migrate/20261118150000_add_kind_to_approval_step_approvers")
require Rails.root.join("db/migrate/20261118150100_keep_team_managers_in_orders_roles")

# The approval step migrations run with today's models loaded: undone back
# to the orders_approval_steps setting and run again from it, through the
# schema before approver rows had kinds.
class Orders::ApprovalStepsMigrationChainTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  def migrate(migration, direction)
    ActiveRecord::Migration.suppress_messages { migration.new.migrate(direction) }
  ensure
    [ ApprovalStep, ApprovalStepApprover ].each(&:reset_column_information)
  end

  test "undoing to the setting and migrating again keeps the steps and approvers" do
    steps = [ { key: "mentor", name: "Mentor", minimum: 0, approvers: [ [ @world.approver_badge, @world.club ], [ @world.buyer_badge, nil ] ] },
      { key: "treasurer", name: "Treasurer", minimum: 500, approvers: [ { kind: :team_managers, manager_team: @world.club } ] } ]
    with_orders(@world, approval_steps: steps) do
      migrate(KeepTeamManagersInOrdersRoles, :down)
      migrate(AddKindToApprovalStepApprovers, :down)
      migrate(CreateApprovalSteps, :down)
      saved = JSON.parse(Orders::Lists.stored_setting(:orders_approval_steps))
      assert_equal [ [ "mentor", [ "#{@world.approver_badge.name} > #{@world.club.name}", @world.buyer_badge.name ] ], [ "treasurer", [] ] ],
        saved.map { |step| [ step["key"], step["approvers"] ] }

      migrate(CreateApprovalSteps, :up)
      assert_equal [ [ @world.approver_badge.id, @world.club.id ], [ @world.buyer_badge.id, nil ] ],
        ActiveRecord::Base.connection.select_rows("SELECT badge_id, team_id FROM approval_step_approvers WHERE approval_step_id = " \
          "(SELECT id FROM approval_steps WHERE key = 'mentor') ORDER BY created_at, badge_id = '#{@world.buyer_badge.id}'")
      migrate(AddKindToApprovalStepApprovers, :up)
      migrate(KeepTeamManagersInOrdersRoles, :up)

      assert_equal %w[mentor treasurer], ApprovalStep.ordered.pluck(:key)
      assert_equal [ [ "badge", @world.approver_badge, @world.club ], [ "badge", @world.buyer_badge, nil ], [ "own_team_managers", nil, nil ] ].sort_by(&:inspect),
        ApprovalStep.find_by!(key: "mentor").approvers.map { |row| [ row.kind, row.badge, row.team ] }.sort_by(&:inspect)
      assert_equal %w[own_team_managers], ApprovalStep.find_by!(key: "treasurer").approvers.map(&:kind)
      assert_equal 50_000, ApprovalStep.find_by!(key: "treasurer").minimum_cents
    end
  end
end
