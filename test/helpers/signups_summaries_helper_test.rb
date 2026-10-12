require "test_helper"

# Who a summarized sign-up is for, by the rules of a sheet's My sign-ups.
class SignupsSummariesHelperTest < ActionView::TestCase
  setup do
    @viewer = build_person("Parent")
    @kid = build_person("Kid")
    @grandma = build_person("Grandma")
  end

  test "the viewer's own sign-up needs no note" do
    assert_nil signups_summary_for(build_signup(@viewer, @viewer), @viewer)
  end

  test "someone taking a place for the viewer" do
    assert_equal "Taken for you by Kid World", signups_summary_for(build_signup(@kid, @viewer), @viewer)
  end

  test "someone else taking their own place" do
    assert_equal "For Kid World", signups_summary_for(build_signup(@kid, @kid), @viewer)
  end

  test "the viewer taking a place on someone's behalf" do
    assert_equal "on behalf of Kid World", signups_summary_for(build_signup(@viewer, @kid), @viewer)
  end

  test "someone else taking a place on a third person's behalf" do
    assert_equal "For Grandma World on behalf of Kid World", signups_summary_for(build_signup(@grandma, @kid), @viewer)
  end

  private

  def build_person(first_name)
    Person.create!(first_name: first_name, last_name: "World")
  end

  def build_signup(person, on_behalf_of)
    Signup.new(person: person, on_behalf_of: on_behalf_of, signed_up_by: @viewer)
  end
end
