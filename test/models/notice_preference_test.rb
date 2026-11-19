require "test_helper"

class NoticePreferenceTest < ActiveSupport::TestCase
  setup do
    @alice = people(:one)
    @bob = people(:two)
  end

  test "takes one of the personal choices, once per section" do
    assert NoticePreference.new(person: @alice, key: "orders", delivery: "each").valid?
    assert_not NoticePreference.new(person: @alice, key: "orders", delivery: "both").valid?
    assert_not NoticePreference.new(person: @alice, key: "", delivery: "daily").valid?

    NoticePreference.create!(person: @alice, key: "orders", delivery: "daily")
    assert_not NoticePreference.new(person: @alice, key: "orders", delivery: "off").valid?
    assert NoticePreference.new(person: @bob, key: "orders", delivery: "off").valid?
  end

  test "goes with the person" do
    person = Person.create!(first_name: "Nora", last_name: "North")
    preference = NoticePreference.create!(person: person, key: "orders", delivery: "weekly")
    Person.where(id: person.id).delete_all

    assert_not NoticePreference.exists?(preference.id)
  end

  test "a merge keeps the kept person's choice and moves the others" do
    skip "people can't be merged here" unless defined?(PersonMerger)

    NoticePreference.create!(person: @alice, key: "orders", delivery: "each")
    NoticePreference.create!(person: @bob, key: "orders", delivery: "off")
    NoticePreference.create!(person: @bob, key: "inventory", delivery: "weekly")

    admin = User.create!(email: "notice-merge-admin@example.com", password: "Password1!", admin: true)
    assert PersonMerger.new(keep_nid: @alice.neat_id, drop_nid: @bob.neat_id, keep_login: "keep").merge(actor: admin)

    choices = NoticePreference.where(person: @alice).pluck(:key, :delivery).sort
    assert_equal [ %w[inventory weekly], %w[orders each] ], choices
  end
end
