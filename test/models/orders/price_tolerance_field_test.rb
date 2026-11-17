require "test_helper"

class Orders::PriceToleranceFieldTest < ActiveSupport::TestCase
  include SettingsTestHelper

  test "reads a percentage and an amount, either of them" do
    assert_equal [ "10", "25", true ], fields("10%, 25")
    assert_equal [ "10", nil, true ], fields("10%")
    assert_equal [ nil, "25", true ], fields("25")
    assert_equal [ "5.5", "$7".delete("$"), true ], fields("5.5 %; $7")
    assert_equal [ nil, nil, true ], fields("")
  end

  test "text it can't show is not readable" do
    [ "about ten", "10%, 20%", "5, 6", "-3%" ].each { |text| assert_not Orders::PriceToleranceField.new(text).readable?, text }
  end

  test "saves the text Orders::Config reads" do
    { [ "10", "25" ] => "10%, 25", [ "10", "" ] => "10%", [ "", "25" ] => "25", [ "7.50", "" ] => "7.5%" }.each do |(percent, amount), text|
      saved = Orders::PriceToleranceField.text_from({ "percent" => percent, "amount" => amount }, "99%")
      assert_equal text, saved
      with_settings(orders_price_tolerance: saved) do
        tolerance = Orders::Config.price_tolerance
        assert_equal [ percent.to_d, (amount.to_d * 100).round ], [ tolerance.percent, tolerance.amount_cents ]
      end
    end
  end

  test "an unchanged value keeps its exact text" do
    assert_equal "10 %;25", Orders::PriceToleranceField.text_from({ "percent" => "10", "amount" => "25.0" }, "10 %;25")
  end

  test "bad numbers are not valid and keep the current text" do
    posted = { "percent" => "ten", "amount" => "" }
    assert_not Orders::PriceToleranceField.valid?(posted)
    assert_equal "5%", Orders::PriceToleranceField.text_from(posted, "5%")
  end

  private

  def fields(text)
    field = Orders::PriceToleranceField.new(text)
    [ field.percent, field.amount, field.readable? ]
  end
end
