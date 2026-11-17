require "test_helper"
require "support/orders_world"

class Orders::ApprovalStepsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  test "only admins see and change the steps" do
    with_orders(@world) do
      step = ApprovalStep.find_by!(key: "approval")
      [ @world.manager, @world.mentor, @world.requester ].each do |person|
        sign_in person.user
        get orders_approval_steps_url
        assert_redirected_to root_url
        patch orders_approval_step_url(step), params: { approval_step: { name: "Changed" } }
        assert_redirected_to root_url
      end
      assert_equal "Approval", step.reload.name
    end
  end

  test "the list shows each step's minimum and approvers, active and retired" do
    with_orders(@world, **two_step_settings(@world, minimum: 500)) do
      ApprovalStep.create!(name: "Board", minimum: "5000", active: false)
      sign_in @world.admin.user

      get orders_approval_steps_url
      assert_response :success
      assert_select "h1", "Approval Steps"
      assert_select "#approval_steps_active li", 2
      assert_select "#approval_steps_active li:first-child", /Mentor\s+Every request\.\s+Approved by team managers, #{Regexp.escape(@world.approver_badge.name)} \(up to #{Regexp.escape(@world.club.name)}\)\./
      assert_select "#approval_steps_active li:last-child", /Treasurer\s+Requests of \$500\.00 or more\./
      assert_select "#approval_steps_retired li", /Board/
      assert_select "#approval_steps_active button, #approval_steps_retired button", text: "Delete", count: 0
    end
  end

  test "an admin adds a step with a minimum and approvers" do
    with_orders(@world) do
      sign_in @world.admin.user
      get new_orders_approval_step_url
      assert_select "select[name='approval_step[approvers_attributes][0][team_id]'] option[value='']", "Up to: every team"

      post orders_approval_steps_url, params: { approval_step: { name: "Treasurer", minimum: "750.25", approvers_attributes: {
        "0" => { badge_id: @world.funder_badge.id, team_id: "" } } } }
      assert_redirected_to orders_approval_steps_url

      step = ApprovalStep.find_by!(name: "Treasurer")
      assert_equal [ "treasurer", 75_025 ], [ step.key, step.minimum_cents ]
      assert_equal [ [ @world.funder_badge, nil ] ], step.approvers.map { |row| [ row.badge, row.team ] }
      assert_equal %w[approval treasurer], Orders::Config.approval_steps.map(&:key)
    end
  end

  test "editing changes the name, minimum and approvers but never the key" do
    with_orders(@world) do
      step = ApprovalStep.find_by!(key: "approval")
      approver = step.approvers.first
      sign_in @world.admin.user

      get edit_orders_approval_step_url(step)
      assert_select "select[name='approval_step[approvers_attributes][0][badge_id]'] option[selected]", @world.approver_badge.name
      assert_select "select[name='approval_step[approvers_attributes][0][team_id]'] option[selected]", "Up to: #{@world.club.name}"

      patch orders_approval_step_url(step), params: { approval_step: { name: "Mentor", minimum: "0", key: "mentor", approvers_attributes: {
        "0" => { id: approver.id, badge_id: approver.badge_id, team_id: approver.team_id, _destroy: "1" },
        "1" => { badge_id: @world.buyer_badge.id, team_id: @world.robotics.id } } } }
      assert_redirected_to orders_approval_steps_url

      step.reload
      assert_equal [ "Mentor", "approval" ], [ step.name, step.key ]
      assert_equal [ [ @world.buyer_badge, @world.robotics ] ], step.approvers.map { |row| [ row.badge, row.team ] }
    end
  end

  test "a bad minimum shows the form again" do
    with_orders(@world) do
      step = ApprovalStep.find_by!(key: "approval")
      sign_in @world.admin.user

      patch orders_approval_step_url(step), params: { approval_step: { name: "", minimum: "-5" } }
      assert_response :unprocessable_entity
      assert_equal "Approval", step.reload.name
    end
  end

  test "steps move, retire and restore" do
    with_orders(@world, **two_step_settings(@world)) do
      treasurer = ApprovalStep.find_by!(key: "treasurer")
      sign_in @world.admin.user

      patch move_orders_approval_step_url(treasurer, direction: "up")
      assert_equal %w[treasurer mentor], Orders::Config.approval_steps.map(&:key)

      patch retire_orders_approval_step_url(treasurer)
      assert_equal [ "mentor" ], Orders::Config.approval_steps.map(&:key)

      patch restore_orders_approval_step_url(treasurer)
      assert_includes Orders::Config.approval_steps.map(&:key), "treasurer"
    end
  end
end
