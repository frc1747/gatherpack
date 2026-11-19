require "test_helper"
require "support/orders_world"

# The orders lists' starting rows, and turning the old settings and stored
# text into rows (what the migrations that made the lists run).
class Orders::ListsTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  # The text column purchases had before payment methods were a list, for
  # the block. Prepared statements are dropped on the way in and out, since
  # a SELECT prepared with the other set of columns can't run again.
  def with_paid_with_column
    connection = ActiveRecord::Base.connection
    connection.add_column :purchases, :paid_with, :string
    connection.clear_cache!
    yield ->(purchase, text) { connection.exec_update("UPDATE purchases SET paid_with = $1 WHERE id = $2", "paid with", [ text, purchase.id ]) }
  ensure
    connection.remove_column :purchases, :paid_with
    connection.clear_cache!
  end

  def purchase(**attributes)
    with_orders(@world) { buy(@world, approved_request(@world).order_lines.to_a, **attributes) }
  end

  test "the starting rows are seeded once" do
    PaymentMethod.delete_all
    DeliveryProblemKind.delete_all

    Orders::Lists.seed!
    Orders::Lists.seed!

    assert_equal [ [ "Team card", false ], [ "Paid personally", true ] ], PaymentMethod.ordered.pluck(:name, :reimburse)
    assert_equal [ [ "Damaged", "damaged" ], [ "Wrong item", "wrong_item" ] ], DeliveryProblemKind.ordered.pluck(:name, :key)
    assert_equal [ [ "Approval", "approval", 0 ] ], ApprovalStep.ordered.pluck(:name, :key, :minimum_cents)
    assert_equal [ "own_team_managers" ], ApprovalStep.find_by!(key: "approval").approvers.map(&:kind)
  end

  test "payment methods come from the defaults, the saved setting and the text purchases were paid with" do
    PaymentMethod.delete_all
    team = purchase
    own = purchase(reimburse_to: @world.buyer)
    cash = purchase
    blank = purchase
    with_paid_with_column do |paid_with|
      paid_with.call(team, "Team card")
      paid_with.call(own, "Own money")
      paid_with.call(cash, " cash ")
      paid_with.call(blank, "")
      setting = JSON.generate([ { "label" => "Team card", "reimburse" => false }, { "label" => "Grant card", "reimburse" => false },
        { "label" => "Cash", "reimburse" => true } ])

      Orders::Lists.convert_payment_methods!(setting)

      assert_equal [ [ "Team card", false ], [ "Paid personally", true ], [ "Grant card", false ], [ "Cash", true ], [ "Own money", true ] ],
        PaymentMethod.ordered.pluck(:name, :reimburse)
      assert_equal [ "Team card", "Own money", "Cash", nil ], [ team, own, cash, blank ].map { |each| each.reload.payment_method&.name }
    end
  end

  test "the old default paid with choices aren't added unless a purchase used them" do
    PaymentMethod.delete_all
    used = purchase(reimburse_to: @world.buyer)
    with_paid_with_column do |paid_with|
      paid_with.call(used, "Personal card — reimburse")

      Orders::Lists.convert_payment_methods!(JSON.generate(Orders::Lists::OLD_DEFAULT_PAID_WITH))

      assert_equal [ "Team card", "Paid personally", "Personal card — reimburse" ], PaymentMethod.ordered.pluck(:name)
      assert used.reload.payment_method.reimburse
      assert used.reimburse?
    end
  end

  test "approval steps come from the saved setting, keeping keys, names and minimums" do
    setting = JSON.generate([
      { "key" => "mentor", "name" => "Mentor", "minimum" => 0,
        "approvers" => [ "#{@world.approver_badge.name} > #{@world.club.name}", @world.buyer_badge.name.upcase ] },
      { "key" => "treasurer", "name" => "Treasurer", "minimum" => 500.5,
        "approvers" => [ "No Such Badge > #{@world.club.name}", "#{@world.funder_badge.name} > No Such Team" ] }
    ])

    skipped = Orders::Lists.convert_approval_steps!(setting)

    assert_equal [ [ "mentor", "Mentor", 0 ], [ "treasurer", "Treasurer", 50050 ] ], ApprovalStep.ordered.pluck(:key, :name, :minimum_cents)
    mentor = ApprovalStep.find_by!(key: "mentor")
    assert_equal [ [ @world.approver_badge, @world.club ], [ @world.buyer_badge, nil ] ], mentor.approvers.map { |row| [ row.badge, row.team ] }
    assert_equal [ "Treasurer: approver not found, left out: No Such Badge > #{@world.club.name}",
      "Treasurer: approver not found, left out: #{@world.funder_badge.name} > No Such Team" ], skipped
    assert_empty ApprovalStep.find_by!(key: "treasurer").approvers
    assert_equal [], Orders::Lists.convert_approval_steps!(setting), "runs once"
    assert_equal 2, ApprovalStep.count
  end

  test "a first step with a minimum gets 0, with a warning" do
    setting = JSON.generate([ { "key" => "approval", "name" => "Approval", "minimum" => 100, "approvers" => [] },
      { "key" => "treasurer", "name" => "Treasurer", "minimum" => 500, "approvers" => [] } ])

    skipped = Orders::Lists.convert_approval_steps!(setting)

    assert_equal [ [ "approval", 0 ], [ "treasurer", 50_000 ] ], ApprovalStep.ordered.pluck(:key, :minimum_cents)
    assert_equal [ "Approval: minimum $100.00 dropped, the first step is needed by every request" ], skipped
  end

  test "a blank or unreadable approval steps setting gives the default step" do
    [ nil, "", "{not json", "[]" ].each do |setting|
      ApprovalStep.delete_all
      assert_equal [], Orders::Lists.convert_approval_steps!(setting)
      assert_equal [ [ "approval", "Approval", 0 ] ], ApprovalStep.pluck(:key, :name, :minimum_cents)
    end
  end

  test "approvals given before the conversion still match their step" do
    with_orders(@world) do
      order_request = submitted_request(@world, lines: [ { description: "Robot kit", price: 600 } ])
      OrderApproval.create!(order_request: order_request, step_key: "mentor", approver: @world.mentor, decision: :approved)
    end
    ApprovalStep.delete_all
    Orders::Lists.convert_approval_steps!(JSON.generate([
      { "key" => "mentor", "name" => "Mentor", "minimum" => 0, "approvers" => [ "#{@world.approver_badge.name} > #{@world.club.name}" ] },
      { "key" => "treasurer", "name" => "Treasurer", "minimum" => 500, "approvers" => [] }
    ]))
    Orders::Current.reset

    order_request = OrderRequest.last
    assert_equal [ "mentor" ], order_request.approved_step_keys
    assert_equal "treasurer", order_request.current_step.key
    assert_equal "Mentor", order_request.order_approvals.first.step_name
  end

  test "undoing the conversions gives back the settings as the old readers took them" do
    PaymentMethod.find_by!(name: "Paid personally").update!(name: "Own money")
    ApprovalStep.create!(key: "mentor", name: "Mentor", minimum_cents: 0).approvers.create!(badge: @world.approver_badge, team: @world.club)
    ApprovalStep.create!(key: "treasurer", name: "Treasurer", minimum_cents: 25_050)

    assert_equal [ { "label" => "Team card", "reimburse" => false }, { "label" => "Own money", "reimburse" => true } ],
      JSON.parse(Orders::Lists.payment_methods_json)
    assert_equal [ { "key" => "mentor", "name" => "Mentor", "minimum" => 0, "approvers" => [ "#{@world.approver_badge.name} > #{@world.club.name}" ] },
      { "key" => "treasurer", "name" => "Treasurer", "minimum" => 250.5, "approvers" => [] } ], JSON.parse(Orders::Lists.approval_steps_json)
  end
end
