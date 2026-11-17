require "test_helper"
require_relative "../../support/intake_world"

class Intake::EmailChangesTest < ActionDispatch::IntegrationTest
  include IntakeWorld
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    build_intake_world
    @person = create_intake_person("Morgan", "Lee", email: "morgan@exampel.com", birthday: 40.years.ago.to_date)
    @registration.entries.create!(first_name: "Morgan", last_name: "Lee", person: @person, verified_at: Time.current, facts: { "team_ids" => [ @mentors.id ] })
  end

  def request_change(email)
    sign_in @person.user
    with_intake do
      post intake_me_email_path(@registration.slug), params: { email: email }
      capture_intake_mail { perform_enqueued_jobs(only: Intake::EmailChangeJob) }
    end
  end

  test "the new email is confirmed before the login changes" do
    sent = request_change("Morgan@Example.com")

    assert_equal "morgan@exampel.com", @person.user.reload.email
    assert_equal [ "morgan@example.com" ], sent.map(&:first)
    token = sent.sole.third[/token=([^"&]+)/, 1]
    sign_out @person.user

    with_intake do
      get intake_email_change_path(token: CGI.unescape(token))
      assert_select "h1", "Change your email to morgan@example.com?"
      post intake_email_change_path, params: { token: CGI.unescape(token) }
    end

    user = @person.user.reload
    assert_equal "morgan@example.com", user.email
    assert user.intake_login_verified_at
  end

  test "a change link works once" do
    token = Intake::EmailChange.token(@person.user, "morgan@example.com")
    Intake::EmailChange.apply!(token)

    with_intake { get intake_email_change_path(token: token) }
    assert_response :not_found
  end

  test "a change link expires" do
    token = Intake::EmailChange.token(@person.user, "morgan@example.com")

    travel 49.hours do
      with_intake { post intake_email_change_path, params: { token: token } }
    end
    assert_response :not_found
    assert_equal "morgan@exampel.com", @person.user.reload.email
  end

  test "an address another login has is never taken, and asking says nothing about it" do
    other = create_intake_person("Taken", "Person", email: "taken@example.com")
    sent = request_change("taken@example.com")

    assert_equal "Check your new address for a link to confirm the change.", flash[:notice]
    token = CGI.unescape(sent.sole.third[/token=([^"&]+)/, 1])
    with_intake { post intake_email_change_path, params: { token: token } }
    assert_response :not_found
    assert_equal "taken@example.com", other.user.reload.email
    assert_equal "morgan@exampel.com", @person.user.reload.email
  end

  test "change requests are limited per day" do
    sign_in @person.user
    with_intake(intake_rate_resend_per_day: "1") do
      post intake_me_email_path(@registration.slug), params: { email: "a@example.com" }
      post intake_me_email_path(@registration.slug), params: { email: "b@example.com" }
    end

    assert_equal "Try again in a few minutes.", flash[:alert]
    assert_enqueued_jobs 1, only: Intake::EmailChangeJob
  end

  test "the page shows the email with Change email" do
    sign_in @person.user
    with_intake { get intake_me_path(@registration.slug) }

    assert_match "morgan@exampel.com", response.body
    assert_select "summary", "Change email"
  end
end
