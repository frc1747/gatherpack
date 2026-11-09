require "test_helper"
require_relative "../../support/intake_world"

class Intake::KioskControllerTest < ActionDispatch::IntegrationTest
  include IntakeWorld
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    build_intake_world
    @registration.update!(kiosk: true)
    @kiosk_accounts = Team.create!(name: "Kiosk Accounts", team_type: team_types(:one))
    @device = create_intake_person("Front", "Desk", team: @northwind, manager: true)
    Membership.create!(person: @device, team: @kiosk_accounts)
  end

  def kiosk_params(birth_year: 1990, email: "jamie@example.com", confirmation: email, **guardian)
    { kiosk: { first_name: "Jamie", last_name: "Fox", birth_year: birth_year, email: email, email_confirmation: confirmation,
      team_ids: [ @mentors.id ], **guardian } }
  end

  test "a signed-out device is sent to sign in and back" do
    with_intake { get intake_kiosk_path(@registration.slug) }

    assert_redirected_to new_user_session_path
    assert_equal intake_kiosk_path(@registration.slug), session[:user_return_to]
  end

  test "someone who doesn't manage the registration's team can't open the kiosk" do
    member = create_intake_person("Pat", "Member", team: @kiosk_accounts)
    sign_in member.user
    with_intake(intake_kiosk_users_team: @kiosk_accounts.id) { get intake_kiosk_path(@registration.slug) }

    assert_redirected_to root_path
    assert_equal "The registration kiosk is for kiosk accounts only.", flash[:alert]
  end

  test "a manager of another team can't open it" do
    sign_in @juniors_leader.user
    with_intake { get intake_kiosk_path(@registration.slug) }

    assert_redirected_to root_path
  end

  test "a manager off the kiosk accounts team can't open it when one is set" do
    sign_in @leader.user
    with_intake(intake_kiosk_users_team: @kiosk_accounts.id) { get intake_kiosk_path(@registration.slug) }

    assert_redirected_to root_path
  end

  test "a kiosk team that doesn't exist lets nobody but admins in" do
    sign_in @device.user
    with_intake(intake_kiosk_users_team: "Kiosk Accounts") { get intake_kiosk_path(@registration.slug) }
    assert_redirected_to root_path

    sign_in @admin.user
    with_intake(intake_kiosk_users_team: "Kiosk Accounts") { get intake_kiosk_path(@registration.slug) }
    assert_response :success
  end

  test "a manager on the kiosk accounts team opens it, with no names, photos or links out" do
    sign_in @device.user
    with_intake(intake_kiosk_users_team: @kiosk_accounts.id) { get intake_kiosk_path(@registration.slug) }

    assert_response :success
    assert_select "input[name='kiosk[email_confirmation]']"
    assert_no_match "Front Desk", response.body
    assert_select "a[href='/']", 0
    assert_select "nav", 0
  end

  test "a registration without the kiosk switch has no kiosk" do
    @registration.update!(kiosk: false)
    sign_in @device.user
    with_intake { get intake_kiosk_path(@registration.slug) }

    assert_response :not_found
  end

  test "a kiosk sign-up makes the person, a not-yet-verified login and the applications at once" do
    sign_in @device.user
    with_intake do
      assert_difference -> { Person.count } => 1, -> { User.count } => 1, -> { MembershipApplication.count } => 1 do
        assert_enqueued_with(job: Intake::EntryEmailJob) do
          post intake_kiosk_path(@registration.slug), params: kiosk_params
        end
      end
    end

    assert_response :success
    assert_select "h1", "Thanks, Jamie. Check your email to finish."
    user = User.find_by!(email: "jamie@example.com")
    assert_nil user.intake_login_verified_at
    application = user.person.membership_applications.sole
    assert application.source_kiosk?
    assert_equal @registration, application.registration
    entry = Intake::Entry.sole
    assert entry.source_kiosk?
    assert_nil entry.verified_at
    assert_equal @device.user.id, AuditLog.where(item_type: "Intake::Entry", item_id: entry.id).last.whodunnit
  end

  test "the invitation sets the password and verifies the login" do
    sign_in @device.user
    with_intake { post intake_kiosk_path(@registration.slug), params: kiosk_params }
    sign_out @device.user
    entry = Intake::Entry.sole
    token = entry.issue_token!

    with_intake do
      get intake_verification_path(token: token)
      assert_select "input[name=password]"
      post intake_verification_path, params: { token: token, password: "Password1!", password_confirmation: "Password1!" }
    end

    user = User.find_by!(email: "jamie@example.com")
    assert user.intake_login_verified_at
    assert user.valid_password?("Password1!")
    assert entry.reload.verified_at
  end

  test "mismatched emails are refused" do
    sign_in @device.user
    with_intake do
      assert_no_difference -> { Person.count } do
        post intake_kiosk_path(@registration.slug), params: kiosk_params(confirmation: "jamie@exampel.com")
      end
    end

    assert_response :unprocessable_content
    assert_match "The two emails don&#39;t match.", response.body
  end

  test "a young person needs a guardian's email, which gets the first email" do
    sign_in @device.user
    young_year = Date.current.year - 12
    with_intake do
      post intake_kiosk_path(@registration.slug), params: kiosk_params(birth_year: young_year)
      assert_response :unprocessable_content
      assert_match "Enter a guardian&#39;s name and email.", response.body

      post intake_kiosk_path(@registration.slug), params: kiosk_params(birth_year: young_year,
        guardian_first_name: "Robin", guardian_last_name: "Fox", guardian_email: "robin.fox@example.com")
    end

    # The guardian's request goes; the young person's own invitation waits for the guardian.
    sent = capture_intake_mail { perform_enqueued_jobs(only: [ Intake::GuardianEmailJob, Intake::EntryEmailJob ]) }
    assert_equal [ "robin.fox@example.com" ], sent.map(&:first)
  end

  test "a guardian's confirmation sends the young person's invitation" do
    sign_in @device.user
    with_intake do
      post intake_kiosk_path(@registration.slug), params: kiosk_params(birth_year: Date.current.year - 12,
        guardian_first_name: "Robin", guardian_last_name: "Fox", guardian_email: "robin.fox@example.com")
    end
    sign_out @device.user
    row = Intake::HouseholdMember.guardian.sole
    token = row.issue_token!

    with_intake do
      post intake_guardian_confirmation_path, params: { token: token, password: "Password1!", password_confirmation: "Password1!" }
      assert_enqueued_with(job: Intake::EntryEmailJob)
    end
    jamie = User.find_by!(email: "jamie@example.com").person
    assert_equal [ "Robin" ], jamie.guardians.pluck(:first_name)
  end

  test "an email with a login gets no new records and the same screen" do
    existing = create_intake_person("Jamie", "Fox", email: "jamie@example.com", birthday: 30.years.ago.to_date)
    sign_in @device.user

    with_intake do
      assert_no_difference -> { User.count + Person.count } do
        post intake_kiosk_path(@registration.slug), params: kiosk_params(email: "JAMIE@example.com ")
      end
    end

    assert_select "h1", "Thanks, Jamie. Check your email to finish."
    assert_equal [ @mentors ], existing.membership_applications.map(&:team)
    assert existing.membership_applications.sole.source_kiosk?
  end

  test "the kiosk is limited per device account" do
    sign_in @device.user
    with_intake(intake_rate_kiosk_per_minute: "2") do
      3.times { |i| post intake_kiosk_path(@registration.slug), params: kiosk_params(email: "p#{i}@example.com") }
    end

    assert_response :too_many_requests
    assert_equal 2, Intake::Entry.count
  end

  test "waiting to finish shows kiosk sign-ups with their age, matches and guardian state" do
    placeholder = Person.create!(first_name: "Jamie", last_name: "Fox")
    sign_in @device.user
    with_intake { post intake_kiosk_path(@registration.slug), params: kiosk_params }
    Intake::Entry.sole.update_column(:created_at, 4.days.ago)

    sign_in @leader.user
    with_intake { get waiting_intake_registration_path(@registration) }

    assert_response :success
    assert_match "Email not opened", response.body
    assert_match "Might be the same person as", response.body
    assert_select "a[href='#{person_path(placeholder)}']"
  end

  test "waiting to finish is for the registration's managers" do
    sign_in @juniors_leader.user
    with_intake { get waiting_intake_registration_path(@registration) }

    assert_response :not_found
  end
end
