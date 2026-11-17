require "test_helper"

class HooksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    @admin = create_user("admin@example.com", admin: true)
    @architect = create_user("architect@example.com", admin: true, architect: true)
    @hook = Hook.create!(name: "Sync", event: "people - update", code: "Rails.logger.info('sync')")
  end

  test "an admin who isn't an architect can't delete a hook" do
    sign_in @admin

    delete hook_path(@hook)

    assert Hook.exists?(@hook.id), "a non-architect admin deleted a hook"
  end

  test "an architect can delete a hook" do
    sign_in @architect

    delete hook_path(@hook)

    assert_not Hook.exists?(@hook.id)
    assert_redirected_to hooks_path
  end

  test "the hook page offers Delete only to architects" do
    sign_in @admin
    get hook_path(@hook)
    assert_response :success
    assert_select "a[href=?][data-turbo-method=delete]", hook_path(@hook), count: 0

    sign_in @architect
    get hook_path(@hook)
    assert_select "a[href=?][data-turbo-method=delete]", hook_path(@hook), count: 1
  end

  private

  def create_user(email, **flags)
    user = User.create!(email: email, password: "Password1!", **flags)
    Person.create!(user: user, first_name: "Test", last_name: "Person")
    user
  end
end
