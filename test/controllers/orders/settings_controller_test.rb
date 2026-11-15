require "test_helper"
require "support/orders_world"

class Orders::SettingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OrdersWorld

  setup { @world = build_orders_world }

  def params_for(**overrides)
    {
      steps: { "0" => { key: "approval", name: "Mentor", minimum: "0", approvers: "#{@world.approver_badge.name} > #{@world.club.name}" },
               "1" => { key: "", name: "Treasurer review", minimum: "250.50", approvers: "" },
               "2" => { key: "", name: "", minimum: "", approvers: "" } },
      paid_with: { "0" => { label: "Team card", reimburse: "0" }, "1" => { label: "Cash — reimburse", reimburse: "1" },
                   "2" => { label: "", reimburse: "0" } },
      tolerance_percent: "15", tolerance_amount: "40"
    }.merge(overrides)
  end

  test "only admins see and change the editors" do
    with_orders(@world) do
      [ @world.manager, @world.buyer, @world.mentor, @world.requester ].each do |person|
        sign_in person.user
        get orders_settings_url
        assert_redirected_to root_url
        patch orders_settings_url, params: params_for
        assert_redirected_to root_url
      end
      assert_equal "approval", Orders::Config.approval_steps.first.key
      assert_equal 1, Orders::Config.approval_steps.size
    end
  end

  test "the form shows the current values" do
    with_orders(@world) do
      sign_in @world.admin.user
      get orders_settings_url
      assert_response :success
      assert_select "input[name='steps[0][name]'][value=Approval]"
      assert_select "input[name='paid_with[1][label]'][value='Personal card — reimburse']"
      assert_select "input[name=tolerance_percent][value='10']"
    end
  end

  test "an admin saves steps, paid with choices and tolerance, which the app then reads" do
    with_orders(@world) do
      sign_in @world.admin.user

      patch orders_settings_url, params: params_for
      assert_redirected_to orders_settings_url

      steps = Orders::Config.approval_steps
      assert_equal %w[approval treasurer_review], steps.map(&:key)
      assert_equal [ "Mentor", "Treasurer review" ], steps.map(&:name)
      assert_equal [ 0, 25050 ], steps.map(&:minimum_cents)
      assert_equal [ "#{@world.approver_badge.name} > #{@world.club.name}" ], steps.first.approvers
      assert_equal [ [ "Team card", false ], [ "Cash — reimburse", true ] ], Orders::Config.paid_with.map { |choice| [ choice.label, choice.reimburse ] }
      tolerance = Orders::Config.price_tolerance
      assert_equal [ 15, 4000 ], [ tolerance.percent, tolerance.amount_cents ]
    end
  end

  test "a step keeps its key when renamed" do
    with_orders(@world) do
      sign_in @world.admin.user
      patch orders_settings_url, params: params_for
      assert_equal "approval", Orders::Config.approval_steps.first.key
    end
  end

  test "a new step whose numbered key is taken still gets a free key" do
    with_orders(@world, orders_approval_steps: JSON.generate([
      { "key" => "approval", "name" => "Approval", "minimum" => 0, "approvers" => [] },
      { "key" => "approval_2", "name" => "Second", "minimum" => 0, "approvers" => [] },
      { "key" => "approval_3", "name" => "Third", "minimum" => 0, "approvers" => [] }
    ])) do
      sign_in @world.admin.user

      Timeout.timeout(5) do
        patch orders_settings_url, params: params_for(steps: {
          "0" => { key: "approval", name: "Approval", minimum: "0", approvers: "" },
          "1" => { key: "", name: "Approval", minimum: "0", approvers: "" },
          "2" => { key: "approval_3", name: "Third", minimum: "0", approvers: "" }
        })
      end
      assert_redirected_to orders_settings_url
      assert_equal %w[approval approval_2 approval_3], Orders::Config.approval_steps.map(&:key)
    end
  end

  test "a tolerance of zero and zero is kept, so any rise needs approving again" do
    with_orders(@world) do
      sign_in @world.admin.user

      patch orders_settings_url, params: params_for(tolerance_percent: "0", tolerance_amount: "0")
      assert_redirected_to orders_settings_url
      tolerance = Orders::Config.price_tolerance
      assert_equal [ 0, 0 ], [ tolerance.percent, tolerance.amount_cents ]
      assert_equal 0, tolerance.allowance_cents(10_000)

      get orders_settings_url
      assert_select "input[name=tolerance_percent][value='0']"
      assert_select "input[name=tolerance_amount][value='0']"
    end
  end

  test "bad input is refused and nothing is saved" do
    with_orders(@world) do
      sign_in @world.admin.user
      before = Settings[:orders_approval_steps]

      patch orders_settings_url, params: params_for(
        steps: { "0" => { key: "approval", name: "Mentor", minimum: "lots", approvers: "No Such Badge > Nowhere" } },
        tolerance_percent: "ten"
      )
      assert_response :unprocessable_entity
      assert_match "minimum must be a number", response.body
      assert_match "no badge named", response.body
      assert_match "tolerance percentage", response.body
      assert_equal before, Settings[:orders_approval_steps]
    end
  end

  test "at least one step and one way to pay are kept" do
    with_orders(@world) do
      sign_in @world.admin.user
      patch orders_settings_url, params: params_for(steps: {}, paid_with: {})
      assert_response :unprocessable_entity
      assert_match "at least one approval step", response.body
      assert_match "at least one way", response.body
    end
  end

  test "an unnamed team in an approver line is refused" do
    with_orders(@world) do
      sign_in @world.admin.user
      patch orders_settings_url, params: params_for(
        steps: { "0" => { key: "approval", name: "Mentor", minimum: "0", approvers: "#{@world.approver_badge.name} > Atlantis" } }
      )
      assert_response :unprocessable_entity
      assert_match "no team named", response.body
    end
  end
end
