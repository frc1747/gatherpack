require "test_helper"
require "support/orders_world"

class PaymentMethodTest < ActiveSupport::TestCase
  include OrdersWorld

  setup { @world = build_orders_world }

  test "the reimburse flag says whether the buyer is paid back" do
    with_orders(@world) do
      card = buy(@world, approved_request(@world).order_lines.to_a, payment_method: payment_method("Team card"))
      own = buy(@world, approved_request(@world).order_lines.to_a, payment_method: payment_method("Paid personally"))
      none = buy(@world, approved_request(@world).order_lines.to_a)

      assert_not card.reimburse?
      assert own.reimburse?
      assert_not none.reimburse?

      payment_method("Team card").update!(reimburse: true)
      assert card.reload.reimburse?
    end
  end

  test "the last active one can't be retired or deleted, so Record purchase always has a choice" do
    card = payment_method("Team card")
    personal = payment_method("Paid personally")
    personal.retire!

    assert_raises(ActiveRecord::RecordInvalid) { card.retire! }
    assert_includes card.errors[:base], "Team card is the only active payment method. Add or restore another before retiring or deleting it."
    assert_not card.destroy
    assert card.reload.active?

    personal.restore!
    card.retire!
    assert card.reload.retired?
  end

  test "one in use is retired or merged, not deleted, and old purchases keep it" do
    with_orders(@world) do
      card = payment_method("Team card")
      purchase = buy(@world, approved_request(@world).order_lines.to_a, payment_method: card)

      assert_not card.destroy
      card.retire!
      assert_equal card, purchase.reload.payment_method
      assert_not_includes PaymentMethod.active, card

      card.merge_into!(payment_method("Paid personally"))
      assert_equal "Paid personally", purchase.reload.payment_method.name
    end
  end
end
