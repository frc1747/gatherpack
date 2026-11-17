require "test_helper"

class ImpersonationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    @team = Team.create!(name: "Den A", team_type: team_types(:one))
    @admin = create_person("admin@example.com", "Ada", "Admin", admin: true)
    @member = create_person("member@example.com", "Max", "Member")
  end

  test "impersonation ends when the true user is no longer an admin" do
    sign_in @admin.user
    post impersonate_person_path(@member)
    get edit_person_user_path(@member)
    assert_response :success, "precondition: impersonating the member"

    @admin.user.update!(admin: false)

    get edit_person_user_path(@member)
    refute_equal @member.user.id, controller.current_user&.id,
      "the former admin still acts as the member after losing admin (impersonation not re-checked)"
    assert_redirected_to root_path
    assert_nil session[:impersonated_user_id]
  end

  test "an admin keeps impersonating while still allowed to" do
    sign_in @admin.user
    post impersonate_person_path(@member)

    travel 30.minutes do
      get edit_person_user_path(@member)
      assert_response :success
      assert_equal @member.user.id, controller.current_user.id
    end
  end

  test "impersonation ends after an hour" do
    sign_in @admin.user
    post impersonate_person_path(@member)

    travel 61.minutes do
      get edit_person_user_path(@member)
      assert_redirected_to root_path
      assert_nil session[:impersonated_user_id]
      assert_equal @admin.user.id, controller.current_user.id
    end
  end

  test "starting and stopping an impersonation is in the audit log" do
    sign_in @admin.user

    assert_difference -> { AuditLog.where(item: @member.user, event: "impersonate", whodunnit: @admin.user.id).count }, 1 do
      post impersonate_person_path(@member)
    end
    assert_difference -> { AuditLog.where(item: @member.user, event: "stop_impersonating", whodunnit: @admin.user.id).count }, 1 do
      post stop_impersonating_people_path
    end
  end

  test "an impersonation that is ended for the true user is in the audit log" do
    sign_in @admin.user
    post impersonate_person_path(@member)
    @admin.user.update!(admin: false)

    assert_difference -> { AuditLog.where(item: @member.user, event: "stop_impersonating", whodunnit: @admin.user.id).count }, 1 do
      get root_path
    end
  end

  test "signing out while impersonating logs the end of the impersonation" do
    sign_in @admin.user
    post impersonate_person_path(@member)

    assert_difference -> { AuditLog.where(item: @member.user, event: "stop_impersonating").count }, 1 do
      delete destroy_user_session_path
    end
  end

  test "signing out after the impersonation has expired signs out" do
    sign_in @admin.user
    post impersonate_person_path(@member)

    travel 61.minutes do
      assert_difference -> { AuditLog.where(item: @member.user, event: "stop_impersonating", whodunnit: @admin.user.id).count }, 1 do
        delete destroy_user_session_path
      end
      get people_path
      assert_redirected_to new_user_session_path
    end
  end

  test "an impersonation that ends because the session timed out is in the audit log" do
    post user_session_path, params: { user: { email: @admin.user.email, password: "Password1!" } }
    post impersonate_person_path(@member)

    travel User.timeout_in + 1.minute do
      assert_difference -> { AuditLog.where(item: @member.user, event: "stop_impersonating", whodunnit: @admin.user.id).count }, 1 do
        get people_path
      end
      assert_nil session[:impersonated_user_id]
    end
  end

  test "the audit log shows impersonation entries and can't revert them" do
    sign_in @admin.user
    post impersonate_person_path(@member)
    post stop_impersonating_people_path
    entry = AuditLog.find_by!(item: @member.user, event: "impersonate")

    get audit_logs_path
    assert_response :success
    get audit_log_path(entry)
    assert_response :success
    assert_select "a", text: "Revert", count: 0

    assert_no_changes -> { @member.user.reload.attributes } do
      post revert_audit_log_path(entry)
    end
    assert_response :success
  end

  test "every page says who is being impersonated" do
    sign_in @admin.user
    post impersonate_person_path(@member)

    get people_path

    assert_select ".impersonation-banner", text: /Ada Admin is impersonating Max Member/
  end

  private

  def create_person(email, first, last, admin: false)
    user = User.create!(email: email, password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: first, last_name: last)
    Membership.create!(person: person, team: @team)
    person
  end
end
