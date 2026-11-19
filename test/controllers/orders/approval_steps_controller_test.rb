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
      assert_select "#approval_steps_active li:first-child", /Mentor\s+Every request\.\s+Approved by #{Regexp.escape(@world.approver_badge.name)} \(for #{Regexp.escape(@world.club.name)}\) and managers of each team\./
      assert_select "#approval_steps_active li:last-child", /Treasurer\s+Requests of \$500\.00 or more\./
      assert_select "#approval_steps_retired li", /Board/
      assert_select "#approval_steps_active button, #approval_steps_retired button", text: "Delete", count: 0
    end
  end

  test "an admin adds a step with a minimum and approvers" do
    with_orders(@world) do
      sign_in @world.admin.user
      get new_orders_approval_step_url
      assert_select "select[name='approval_step[approvers_attributes][0][team_id]'] option[value='']", "For: every team"

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
      assert_select "select[name='approval_step[approvers_attributes][0][team_id]'] option[selected]", "For: #{@world.club.name}"

      patch orders_approval_step_url(step), params: { approval_step: { name: "Mentor", minimum: "0", key: "mentor", approvers_attributes: {
        "0" => { id: approver.id, badge_id: approver.badge_id, team_id: approver.team_id, _destroy: "1" },
        "1" => { badge_id: @world.buyer_badge.id, team_id: @world.robotics.id } } } }
      assert_redirected_to orders_approval_steps_url

      step.reload
      assert_equal [ "Mentor", "approval" ], [ step.name, step.key ]
      assert_equal [ [ "own_team_managers", nil, nil ], [ "badge", @world.buyer_badge, @world.robotics ] ],
        step.approvers.map { |row| [ row.kind, row.badge, row.team ] }
    end
  end

  test "the first step's minimum is 0, shown and kept" do
    with_orders(@world, **two_step_settings(@world, minimum: 500)) do
      mentor = ApprovalStep.find_by!(key: "mentor")
      treasurer = ApprovalStep.find_by!(key: "treasurer")
      sign_in @world.admin.user

      get orders_approval_steps_url
      assert_select "p", /Every request needs the first step, so it has no minimum/

      get edit_orders_approval_step_url(mentor)
      assert_select "input[name='approval_step[minimum]'][disabled][value='0.00']"
      assert_select ".form-text", /This is the first step, so every request needs it and it has no minimum/

      patch orders_approval_step_url(mentor), params: { approval_step: { name: "Mentor", minimum: "100" } }
      assert_equal 0, mentor.reload.minimum_cents

      get edit_orders_approval_step_url(treasurer)
      assert_select "input[name='approval_step[minimum]']:not([disabled])"

      patch move_orders_approval_step_url(treasurer, direction: "up")
      assert_equal "Treasurer is now the first step, which every request needs, so its minimum is now $0.", flash[:notice]
      assert_equal 0, treasurer.reload.minimum_cents
      follow_redirect!
      assert_select "#approval_steps_active li:first-child", /Treasurer\s+Every request\./
    end
  end

  test "retiring the first step clears the minimum of the step that takes its place" do
    with_orders(@world, **two_step_settings(@world, minimum: 500)) do
      sign_in @world.admin.user

      patch retire_orders_approval_step_url(ApprovalStep.find_by!(key: "mentor"))
      assert_match "Treasurer is now the first step", flash[:notice]
      assert_equal 0, ApprovalStep.find_by!(key: "treasurer").minimum_cents
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

  test "approver rows can be a badge, the managers of a team or the managers of the request's own team, and redraw as saved" do
    with_orders(@world) do
      sign_in @world.admin.user
      post orders_approval_steps_url, params: { approval_step: { name: "Directors", minimum: "100", approvers_attributes: {
        "0" => { kind: "team_managers", manager_team_id: @world.club.id, team_id: @world.robotics.id },
        "1" => { kind: "own_team_managers", badge_id: @world.funder_badge.id, team_id: @world.art.id },
        "2" => { kind: "badge", badge_id: "", team_id: "" },
        "3" => { kind: "team_managers", manager_team_id: "", team_id: "" } } } }
      assert_redirected_to orders_approval_steps_url

      step = ApprovalStep.find_by!(name: "Directors")
      assert_equal [ [ "team_managers", nil, @world.club, @world.robotics ], [ "own_team_managers", nil, nil, nil ] ],
        step.approvers.map { |row| [ row.kind, row.badge, row.manager_team, row.team ] }

      get orders_approval_steps_url
      assert_select "##{ActionView::RecordIdentifier.dom_id(step)}",
        /Approved by managers of #{Regexp.escape(@world.club.name)} \(for #{Regexp.escape(@world.robotics.name)}\) and managers of each team\./

      get edit_orders_approval_step_url(step)
      assert_select "fieldset[data-controller=orders-grant-rows] p", "Any of these:"
      assert_select "select[name='approval_step[approvers_attributes][0][kind]'] option[selected][value=team_managers]", "Managers of a team"
      assert_select "select[name='approval_step[approvers_attributes][0][manager_team_id]'] option[selected]", @world.club.name
      assert_select "select[name='approval_step[approvers_attributes][0][team_id]'] option[selected]", "For: #{@world.robotics.name}"
      assert_select "select[name='approval_step[approvers_attributes][1][kind]'] option[selected][value=own_team_managers]"
      assert_select "select[name='approval_step[approvers_attributes][2][kind]'] option[selected][value=badge]"

      patch orders_approval_step_url(step), params: { approval_step: { name: "Directors", minimum: "100" } }
      assert_equal 2, step.reload.approvers.count, "saving unchanged keeps the rows"
    end
  end

  test "an approver row is checked for what its kind needs" do
    step = ApprovalStep.create!(name: "Checked", minimum_cents: 0)

    assert_not step.approvers.build(kind: :badge).valid?
    assert_not step.approvers.build(kind: :team_managers).valid?
    own = step.approvers.build(kind: :own_team_managers, badge: @world.approver_badge, team: @world.art)
    assert own.valid?
    assert_equal [ nil, nil ], [ own.badge, own.team ]
    assert_equal "Managers of each team", own.line
  end

  test "the screens no longer say team managers can always approve" do
    with_orders(@world) do
      sign_in @world.admin.user
      [ orders_approval_steps_url, new_orders_approval_step_url, orders_settings_url ].each do |url|
        get url
        assert_no_match(/team managers (can )?always/i, response.body)
      end
    end
  end
end
