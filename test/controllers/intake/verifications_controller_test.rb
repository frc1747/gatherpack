require "test_helper"
require_relative "../../support/intake_world"

class Intake::VerificationsControllerTest < ActionDispatch::IntegrationTest
  include IntakeWorld
  include ActiveJob::TestHelper

  setup do
    host! "localhost"
    build_intake_world
  end

  test "opening the link shows a page and uses nothing" do
    entry, token = create_intake_entry

    with_intake { get intake_verification_path(token: token) }

    assert_response :success
    assert_select "input[name=password]"
    assert_equal entry, Intake::Entry.find_by_token(token)
  end

  test "finishing a new email creates the person, login and applications, and signs them in" do
    entry, token = create_intake_entry(teams: [ @juniors, @mentors ])

    with_intake do
      assert_difference -> { Person.count } => 1, -> { User.count } => 1, -> { MembershipApplication.count } => 2 do
        post intake_verification_path, params: { token: token, password: "Password1!", password_confirmation: "Password1!" }
      end
    end

    assert_redirected_to intake_me_path(@registration.slug)
    user = User.find_by!(email: "riley@example.com")
    assert user.intake_login_verified_at
    assert_equal "Riley", user.person.first_name
    assert_equal [ @juniors, @mentors ].map(&:id).sort, user.person.membership_applications.map(&:team_id).sort
    assert user.person.membership_applications.all? { |application| application.registration == @registration && application.source_link? }
    assert entry.reload.verified_at
    assert_equal user.person, entry.person
    with_intake { follow_redirect! }
    assert_response :success
  end

  test "the link works once" do
    _, token = create_intake_entry

    with_intake do
      post intake_verification_path, params: { token: token, password: "Password1!", password_confirmation: "Password1!" }
      delete destroy_user_session_path
      get intake_verification_path(token: token)
    end

    assert_response :not_found
    assert_select "h1", "This link has expired or was already used."
  end

  test "an expired link and a made-up one say the same" do
    entry, token = create_intake_entry

    pages = []
    with_intake do
      travel_to(entry.expires_at + 1.minute) { get intake_verification_path(token: token) }
      pages << [ response.status, css_select("h1").text ]
      get intake_verification_path(token: "made-up")
      pages << [ response.status, css_select("h1").text ]
    end

    assert_equal 1, pages.uniq.size
    assert_equal 404, pages.first.first
  end

  test "a bad password keeps the link working" do
    _, token = create_intake_entry

    with_intake do
      assert_no_difference -> { User.count + Person.count } do
        post intake_verification_path, params: { token: token, password: "x", password_confirmation: "y" }
      end
    end

    assert_response :unprocessable_content
    assert Intake::Entry.find_by_token(token)
  end

  test "an email that already has a login attaches to that person and never signs in" do
    existing = create_intake_person("Casey", "Quinn", email: "casey@example.com", birthday: 30.years.ago.to_date)
    entry, token = create_intake_entry(first_name: "Casey", email: "CASEY@example.com")

    with_intake do
      assert_no_difference -> { User.count + Person.count } do
        post intake_verification_path, params: { token: token }
      end
    end

    assert_response :success
    assert_select "h1", "You already have an account. Sign in to continue."
    assert_equal existing, entry.reload.person
    assert_equal [ @juniors ], existing.membership_applications.map(&:team)
    get intake_me_path(@registration.slug)
    assert_redirected_to new_user_session_path
  end

  test "too many links opened from one address" do
    _, token = create_intake_entry

    with_intake(intake_rate_verify_per_hour: "2") do
      3.times { get intake_verification_path(token: token) }
    end

    assert_response :too_many_requests
    assert_match "Try again in a few minutes.", response.body
  end

  test "the token is in the query string, which the log filters" do
    _, token = create_intake_entry
    with_intake { get intake_verification_path(token: token) }

    assert_not_includes request.filtered_path, token
  end
end
