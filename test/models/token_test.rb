require "test_helper"

class TokenTest < ActiveSupport::TestCase
  setup do
    @person = people(:one)
  end

  test "a value in the 5700 reader format is stored as the card number" do
    token = Token.create!(value: "5700" + 8675309.to_s(16), tokenable: @person)

    assert_equal "8675309", token.value
  end

  test "a stored value isn't normalised again when the card changes holder" do
    # The reader's 5700153c0fb40 is card number 5700123456, which itself
    # looks like the other reader's format.
    token = Token.create!(value: "5700153c0fb40", tokenable: @person)
    assert_equal "5700123456", token.value

    token.update!(tokenable: people(:two))

    assert_equal "5700123456", token.reload.value
    assert_equal token, Token.find_by_rfid("5700153c0fb40")
  end

  test "a card number can't be added again in the other reader's format" do
    Token.create!(value: "8675309", tokenable: @person)
    token = Token.new(value: "5700" + 8675309.to_s(16), tokenable: people(:two))

    assert_not token.valid?
    assert_includes token.errors[:value], "has already been taken"
  end

  test "find_by_rfid finds a card from either reader's format" do
    token = Token.create!(value: "8675309", tokenable: @person)

    assert_equal token, Token.find_by_rfid("8675309")
    assert_equal token, Token.find_by_rfid("5700" + 8675309.to_s(16).upcase)
  end

  test "the database refuses a second card with the same value" do
    Token.create!(value: "8675309", tokenable: @person)

    assert_raises ActiveRecord::RecordNotUnique do
      Token.new(value: "8675309", tokenable: people(:two)).save!(validate: false)
    end
  end
end
