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

  teardown do
    AuthenticationRateLimits.store = nil
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

  test "a manager can't change the login of an admin who is a member of their team" do
    sign_in @leader.user

    patch person_user_path(@admin), params: { user: new_login("leader-owned@example.com") }

    @admin.user.reload
    assert_equal "admin@example.com", @admin.user.email, "the manager changed the admin's email"
    assert_not @admin.user.valid_password?("Hijacked123!"), "the manager set the admin's password"
  end

  test "a manager can't change the login of the manager of a parent team" do
    pack = Team.create!(name: "Pack", team_type: team_types(:one))
    @team.update!(parent: pack)
    pack_leader = create_member("pack-leader@example.com", "Pat", "Pack")
    Membership.find_by!(person: pack_leader).update!(team: pack, manager: true)
    sign_in @leader.user

    patch person_user_path(pack_leader), params: { user: new_login("leader-owned@example.com") }

    assert_not pack_leader.user.reload.valid_password?("Hijacked123!"),
      "the Den A manager set the password of the Pack manager above them"
  end

  # Only the person themselves or an admin changes a login, even for a member
  # the manager does manage.
  test "a manager can't change the login of a member they manage" do
    sign_in @leader.user

    get person_path(@member)
    assert_select "a[href=?]", edit_person_user_path(@member), count: 0

    patch person_user_path(@member), params: { user: new_login("leader-owned@example.com") }

    @member.user.reload
    assert_equal "member@example.com", @member.user.email
    assert_not @member.user.valid_password?("Hijacked123!")
  end

  test "a member can change their own login with their old password" do
    sign_in @member.user

    patch person_user_path(@member), params: { user: new_login("max@example.com").merge(old_password: "Password1!") }

    assert_redirected_to person_path(@member)
    @member.user.reload
    assert_equal "max@example.com", @member.user.email
    assert @member.user.valid_password?("Hijacked123!")
  end

  test "a member can't change their own password with a wrong old password" do
    sign_in @member.user

    patch person_user_path(@member), params: { user: new_login("member@example.com").merge(old_password: "wrong") }

    assert_response :unprocessable_entity
    assert_not @member.user.reload.valid_password?("Hijacked123!")
  end

  test "changing one's own password requires the current password" do
    sign_in @member.user

    patch person_user_path(@member), params: { user: { password: "NewPass123!", password_confirmation: "NewPass123!" } }

    assert_not @member.user.reload.valid_password?("NewPass123!"), "password changed with no old_password supplied"
    assert_response :unprocessable_entity
  end

  test "a member can change their own password with their current password" do
    sign_in @member.user

    patch person_user_path(@member), params: { user: { password: "NewPass123!", password_confirmation: "NewPass123!", old_password: "Password1!" } }

    assert_redirected_to person_path(@member)
    assert @member.user.reload.valid_password?("NewPass123!")
  end

  test "changing one's own email requires the current password" do
    sign_in @member.user

    patch person_user_path(@member), params: { user: { email: "max@example.com" } }
    assert_response :unprocessable_entity

    patch person_user_path(@member), params: { user: { email: "max@example.com", old_password: "wrong" } }
    assert_response :unprocessable_entity
    assert_equal "member@example.com", @member.user.reload.email

    patch person_user_path(@member), params: { user: { email: "max@example.com", old_password: "Password1!" } }
    assert_redirected_to person_path(@member)
    assert_equal "max@example.com", @member.user.reload.email
  end

  test "an admin changing their own login also needs their current password" do
    sign_in @admin.user

    patch person_user_path(@admin), params: { user: new_login("admin-new@example.com") }

    assert_response :unprocessable_entity
    @admin.user.reload
    assert_equal "admin@example.com", @admin.user.email
    assert_not @admin.user.valid_password?("Hijacked123!")
  end

  test "an admin changes another member's password without giving their own" do
    sign_in @admin.user

    patch person_user_path(@member), params: { user: { password: "NewPass123!", password_confirmation: "NewPass123!" } }

    assert_redirected_to person_path(@member)
    assert @member.user.reload.valid_password?("NewPass123!")
  end

  test "the login form asks for the current password, including for a provider login" do
    sign_in @member.user
    get edit_person_user_path(@member)
    assert_select "input[type=password][name=?]", "user[old_password]"

    @member.user.update_columns(provider: "github", uid: "123")
    get edit_person_user_path(@member)
    assert_select "input[type=password][name=?]", "user[old_password]"
  end

  test "the login form doesn't ask for a current password on someone else's login" do
    sign_in @admin.user
    get edit_person_user_path(@member)
    assert_select "input[type=password][name=?]", "user[password]"
    assert_select "input[name=?]", "user[old_password]", false
  end

  test "saving one's own login unchanged doesn't ask for the current password" do
    sign_in @member.user

    patch person_user_path(@member), params: { user: { email: "MEMBER@example.com", password: "", password_confirmation: "" } }

    assert_redirected_to person_path(@member)
  end

  test "guessing one's own current password is rate limited" do
    AuthenticationRateLimits.store = ActiveSupport::Cache::MemoryStore.new
    sign_in @member.user

    statuses = 11.times.map do |i|
      patch person_user_path(@member), params: { user: new_login("member@example.com").merge(old_password: "guess-#{i}") }
      response.status
    end

    assert_equal [ 422 ] * 10 + [ 429 ], statuses
    assert_not @member.user.reload.valid_password?("Hijacked123!")
  end

  test "an admin changing other people's logins isn't rate limited" do
    AuthenticationRateLimits.store = ActiveSupport::Cache::MemoryStore.new
    sign_in @admin.user

    statuses = 11.times.map do |i|
      patch person_user_path(@member), params: { user: { email: "member-#{i}@example.com" } }
      response.status
    end

    assert_equal [ 303 ] * 11, statuses
  end

  test "guessing the current password on the account page is rate limited" do
    AuthenticationRateLimits.store = ActiveSupport::Cache::MemoryStore.new
    sign_in @member.user

    statuses = 11.times.map do |i|
      put user_registration_path, params: { user: { email: "member@example.com", current_password: "guess-#{i}" } }
      response.status
    end

    assert_equal [ 422 ] * 10 + [ 429 ], statuses
  end

  test "a member can't make their own login a kiosk account" do
    sign_in @member.user

    patch person_user_path(@member), params: { user: { email: "member@example.com", kiosk: "1", old_password: "Password1!" } }

    assert_not @member.user.reload.kiosk?
  end

  test "an admin can make a login a kiosk account and back" do
    sign_in @admin.user

    get edit_person_user_path(@member)
    assert_select "input[type=checkbox][name=?]", "user[kiosk]"

    patch person_user_path(@member), params: { user: { email: "member@example.com", kiosk: "1" } }
    assert @member.user.reload.kiosk?

    patch person_user_path(@member), params: { user: { email: "member@example.com", kiosk: "0" } }
    assert_not @member.user.reload.kiosk?
  end

  test "the login form offers the kiosk flag only to admins" do
    sign_in @member.user

    get edit_person_user_path(@member)

    assert_select "input[name=?]", "user[kiosk]", count: 0
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
