require "test_helper"
require_relative "../../support/intake_world"

class Intake::ApplicationDecisionsTest < ActionDispatch::IntegrationTest
  include IntakeWorld
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    build_intake_world
    @applicant = create_intake_person("Riley", "Rivera", birthday: 30.years.ago.to_date)
    @application = MembershipApplication.create!(person: @applicant, team: @juniors, registration: @registration, source: :link)
    sign_in @leader.user
  end

  test "the applications page shows the source and what approval adds" do
    with_intake { get applications_team_path(@juniors) }

    assert_match "Registration link: Join Northwind", response.body
    assert_match "Will also join: Everyone", response.body
    assert_match "Will get: Joined Online", response.body
  end

  test "approving with a pick adds the picked team" do
    with_intake { patch team_membership_application_path(@juniors, @application), params: { status: "approved", pick_team_id: @class_2032.id } }

    assert @application.reload.approved?
    assert_includes @applicant.teams, @class_2032
    assert_includes @applicant.teams, @everyone
  end

  test "a required pick that isn't chosen stops the approval" do
    @registration.update!(pick_one_required: true)
    with_intake { patch team_membership_application_path(@juniors, @application), params: { status: "approved" } }

    assert @application.reload.pending?
    assert_equal "Choose a team for Riley.", flash[:alert]
  end

  test "denying with a reason keeps it and sends it" do
    with_intake do
      assert_enqueued_jobs 1, only: SendEmailJob do
        patch team_membership_application_path(@juniors, @application), params: { status: "denied", reason: "We're full." }
      end
    end

    assert @application.reload.denied?
    assert_equal "We're full.", @application.reviewer_notes
  end

  test "an admin deletes a denied spam person with their login, after the confirmation" do
    @application.deny!
    sign_in @admin.user
    with_intake do
      get intake_spam_person_path(@applicant)
      assert_response :success
      assert_match "their login", response.body
      delete intake_spam_person_path(@applicant)
    end

    assert_not Person.exists?(@applicant.id)
    assert_not User.exists?(email: @applicant.user.email)
  end

  test "a person with anything else can't be deleted as spam" do
    @application.deny!
    Membership.create!(person: @applicant, team: @everyone)
    sign_in @admin.user
    with_intake { delete intake_spam_person_path(@applicant) }

    assert Person.exists?(@applicant.id)
  end

  test "a manager can't delete spam people" do
    @application.deny!
    with_intake { delete intake_spam_person_path(@applicant) }

    assert Person.exists?(@applicant.id)
  end
end
