require "test_helper"

class PeopleControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    @admin = create_person("admin@example.com", "Ada", "Admin", admin: true)
    @former_admin = create_person("former-admin@example.com", "Former", "Admin", admin: true)
    @member = create_person("member@example.com", "Max", "Member")
  end

  test "an admin can delete a person" do
    sign_in @admin.user

    assert_difference -> { Person.count }, -1 do
      delete person_path(@member)
    end
    assert_redirected_to people_path
  end

  test "deleting a person ends their sign-in" do
    sign_in @admin.user
    delete person_path(@member)

    assert_not User.exists?(@member.user_id),
      "the deleted person's login still exists and can sign in with its old password"
  end

  test "deleting an admin's person removes their admin access" do
    former_user = @former_admin.user
    sign_in @admin.user
    delete person_path(@former_admin)
    sign_out :user
    assert_not Person.exists?(@former_admin.id)

    # Signing back in with the old login, then giving it a new person, must
    # not lead back into the admin pages.
    sign_in former_user
    post people_path, params: { person: { first_name: "Back", last_name: "Again", user_id: former_user.id } }
    get audit_logs_path

    assert_not response.successful?,
      "the deleted person's login re-attached itself to a new person and opened /audit_logs (#{response.status})"
  end

  test "a member's bio can't put script on the profile page" do
    @member.update!(bio: "Hi!\n\n<img src=x onerror=\"alert(1)\">\n\n[site](javascript:alert(document.cookie))")

    sign_in @admin.user
    get person_path(@member)

    assert_response :success
    assert_includes response.body, "<p>Hi!</p>"
    assert_not response.body.match?(/<img[^>]*onerror=/), "the bio renders a live onerror handler"
    assert_not response.body.match?(/href="javascript:/), "the bio renders a javascript: link"
  end

  test "an admin who isn't an architect can't impersonate an architect" do
    architect = create_person("architect@example.com", "Arch", "Itect", admin: true, architect: true)
    sign_in @admin.user

    post impersonate_person_path(architect)
    get new_hook_path

    assert_not_equal 200, response.status, "the admin reached the architect-only hook editor"
    assert_nil session[:impersonated_user_id]
  end

  test "an admin can't reach an architect by impersonating another admin first" do
    architect = create_person("architect@example.com", "Arch", "Itect", admin: true, architect: true)
    sign_in @admin.user

    post impersonate_person_path(@former_admin)
    post impersonate_person_path(architect)
    get new_hook_path

    assert_not_equal 200, response.status, "the admin reached the architect-only hook editor"
  end

  test "an admin can impersonate a member" do
    sign_in @admin.user

    post impersonate_person_path(@member)

    assert_equal @member.user.id.to_s, session[:impersonated_user_id].to_s
  end

  test "an architect can impersonate another architect" do
    architect = create_person("architect@example.com", "Arch", "Itect", admin: true, architect: true)
    other = create_person("other-architect@example.com", "Other", "Itect", admin: true, architect: true)
    sign_in architect.user

    post impersonate_person_path(other)
    get new_hook_path

    assert_response :success
  end

  test "the person page offers Impersonate only when it's allowed" do
    architect = create_person("architect@example.com", "Arch", "Itect", admin: true, architect: true)
    sign_in @admin.user

    get person_path(architect)
    assert_select "a[href=?]", impersonate_person_path(architect), count: 0

    get person_path(@member)
    assert_select "a[href=?]", impersonate_person_path(@member)
  end

  private

  def create_person(email, first, last, admin: false, architect: false)
    user = User.create!(email: email, password: "Password1!", admin: admin, architect: architect)
    Person.create!(user: user, first_name: first, last_name: last)
  end
end
