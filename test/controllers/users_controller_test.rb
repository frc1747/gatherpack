require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    @team = Team.create!(name: "Den A", team_type: team_types(:one))
    @admin = create_member("admin@example.com", "Ada", "Admin", admin: true)
    @leader = create_member("leader@example.com", "Lee", "Leader", manager: true)
    @member = create_member("member@example.com", "Max", "Member")
    @no_login = Person.create!(first_name: "Nora", last_name: "Nologin")
    Membership.create!(person: @no_login, team: @team)
  end

  test "a member cannot replace another person's login" do
    sign_in @member.user
    original_user = @leader.user

    post person_user_path(@leader), params: { user: new_login("member-owned@example.com") }

    assert_equal original_user, @leader.reload.user,
      "a member replaced another person's login with one they control"
  end

  test "a member cannot replace an admin's login" do
    sign_in @member.user
    original_user = @admin.user

    post person_user_path(@admin), params: { user: new_login("member-owned@example.com") }

    assert_equal original_user, @admin.reload.user,
      "a member linked a login they control to the admin's person"
  end

  test "a member cannot attach a login to a person without one" do
    sign_in @member.user

    assert_no_difference -> { User.count } do
      post person_user_path(@no_login), params: { user: new_login("member-owned@example.com") }
    end
    assert_nil @no_login.reload.user
  end

  test "a member cannot open the new login form" do
    sign_in @member.user

    get new_person_user_path(@no_login)

    assert_redirected_to root_path
  end

  test "creating a login never takes over an existing login with no person" do
    sign_in @member.user
    orphan = User.create!(email: "orphan@example.com", password: "Password1!")

    post person_user_path(@no_login), params: { user: new_login("orphan@example.com") }

    assert_not orphan.reload.valid_password?("Hijacked123!"),
      "creating a login set the password of an existing login with no person"
  end

  test "an admin cannot take over an existing login with no person" do
    sign_in @admin.user
    orphan = User.create!(email: "orphan@example.com", password: "Password1!")

    post person_user_path(@no_login), params: { user: new_login("orphan@example.com") }

    assert_response :unprocessable_entity
    assert_not orphan.reload.valid_password?("Hijacked123!")
    assert_nil @no_login.reload.user
  end

  test "an admin cannot replace a person's existing login" do
    sign_in @admin.user
    original_user = @member.user

    get new_person_user_path(@member)
    assert_redirected_to person_path(@member)

    assert_no_difference -> { User.count } do
      post person_user_path(@member), params: { user: new_login("replacement@example.com") }
    end
    assert_redirected_to person_path(@member)
    assert_equal original_user, @member.reload.user
  end

  test "an admin can create a login for a person without one" do
    sign_in @admin.user

    get new_person_user_path(@no_login)
    assert_response :success

    assert_difference -> { User.count }, 1 do
      post person_user_path(@no_login), params: { user: new_login("nora@example.com") }
    end
    assert_redirected_to person_path(@no_login)
    assert_equal "nora@example.com", @no_login.reload.user.email
    assert @no_login.user.valid_password?("Hijacked123!")
  end

  test "the person page offers to create a login only to admins" do
    sign_in @member.user
    get person_path(@no_login)
    assert_response :success
    assert_select "a[href=?]", new_person_user_path(@no_login), count: 0

    sign_in @admin.user
    get person_path(@no_login)
    assert_select "a[href=?]", new_person_user_path(@no_login), count: 1
  end

  test "the profile form offers to create a login only to admins" do
    sign_in @leader.user
    get edit_person_path(@no_login)
    assert_response :success
    assert_select "a[href=?]", new_person_user_path(@no_login), count: 0

    sign_in @admin.user
    get edit_person_path(@no_login)
    assert_select "a[href=?]", new_person_user_path(@no_login), count: 1
  end

  test "an admin who isn't an architect can't change an architect's password" do
    architect = create_member("architect@example.com", "Arch", "Itect", admin: true, architect: true)
    sign_in @admin.user

    patch person_user_path(architect), params: { user: new_login("architect@example.com") }

    assert_not architect.user.reload.valid_password?("Hijacked123!"),
      "the admin set the architect's password and can sign in with architect powers"
  end

  test "an admin who isn't an architect can't remove an architect's admin flag" do
    architect = create_member("architect@example.com", "Arch", "Itect", admin: true, architect: true)
    sign_in @admin.user

    patch person_user_path(architect), params: { user: { admin: "0" } }

    assert architect.user.reload.admin
  end

  test "an architect can change another architect's password" do
    architect = create_member("architect@example.com", "Arch", "Itect", admin: true, architect: true)
    other = create_member("other-architect@example.com", "Other", "Itect", admin: true, architect: true)
    sign_in architect.user

    patch person_user_path(other), params: { user: new_login("other-architect@example.com") }

    assert other.user.reload.valid_password?("Hijacked123!")
  end

  test "an admin can change a member's login" do
    sign_in @admin.user

    patch person_user_path(@member), params: { user: new_login("member-new@example.com") }

    @member.user.reload
    assert_equal "member-new@example.com", @member.user.email
    assert @member.user.valid_password?("Hijacked123!")
  end

  test "the person page offers to change an architect's login only to architects" do
    architect = create_member("architect@example.com", "Arch", "Itect", admin: true, architect: true)

    sign_in @admin.user
    get person_path(architect)
    assert_select "a[href=?]", edit_person_user_path(architect), count: 0
    get edit_person_path(architect)
    assert_select "a[href=?]", edit_person_user_path(architect), count: 0
    get person_path(@member)
    assert_select "a[href=?]", edit_person_user_path(@member), count: 1

    sign_in architect.user
    get person_path(architect)
    assert_select "a[href=?]", edit_person_user_path(architect), count: 1
  end

  private

  def new_login(email)
    { email: email, password: "Hijacked123!", password_confirmation: "Hijacked123!" }
  end

  def create_member(email, first, last, admin: false, architect: false, manager: false)
    user = User.create!(email: email, password: "Password1!", admin: admin, architect: architect)
    person = Person.create!(user: user, first_name: first, last_name: last)
    Membership.create!(person: person, team: @team, manager: manager)
    person
  end
end
