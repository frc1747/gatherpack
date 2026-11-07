require "test_helper"
require_relative "../../support/intake_world"

class Intake::MeControllerTest < ActionDispatch::IntegrationTest
  include IntakeWorld
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    build_intake_world
    @adult = create_intake_person("Morgan", "Lee", birthday: 40.years.ago.to_date)
    @entry = @registration.entries.create!(first_name: "Morgan", last_name: "Lee", person: @adult, verified_at: Time.current,
      facts: { "team_ids" => [ @mentors.id ] })
    Intake::Enrollment.new(@entry).apply(@adult)
    @ward = Intake::Enrollment.new(@entry).add_ward(adder: @adult, first_name: "Sam", last_name: "Lee", teams: [ @juniors.id ])
    @other_applicant = create_intake_person("Taylor", "Stone", birthday: 35.years.ago.to_date)
    MembershipApplication.create!(person: @other_applicant, team: @mentors, registration: @registration, source: :link)
  end

  test "signing in is required" do
    with_intake { get intake_me_path(@registration.slug) }

    assert_redirected_to new_user_session_path
  end

  test "the page shows the person and their wards, and nobody else" do
    sign_in @adult.user
    with_intake { get intake_me_path(@registration.slug) }

    assert_response :success
    assert_match "Mentors", response.body
    assert_match "Sam Lee", response.body
    assert_no_match "Taylor", response.body
    assert_select "h1", "Join Northwind"
  end

  test "an applicant sees only themselves among people" do
    sign_in @other_applicant.user
    get people_path

    assert_equal [ @other_applicant ], PersonPolicy::Scope.new(@other_applicant.user, Person).resolve.to_a
    assert_no_match "Morgan", response.body
  end

  test "a guardian acts for their ward" do
    sign_in @adult.user
    with_intake { patch intake_me_person_path(@registration.slug, @ward), params: { person: { birthday: "2015-04-03" } } }

    assert_redirected_to intake_me_path(@registration.slug)
    assert_equal Date.new(2015, 4, 3), @ward.reload.birthday
  end

  test "a guardian can't act for someone else" do
    sign_in @adult.user
    with_intake { patch intake_me_person_path(@registration.slug, @other_applicant), params: { person: { birthday: "2015-04-03" } } }

    assert_response :not_found
    assert_equal 35.years.ago.to_date, @other_applicant.reload.birthday
  end

  test "nobody can withdraw someone else's application" do
    application = @other_applicant.membership_applications.sole
    sign_in @adult.user
    with_intake { delete intake_me_application_path(@registration.slug, application) }

    assert_response :not_found
    assert application.reload.pending?
  end

  test "a guardian withdraws their ward's application" do
    application = @ward.membership_applications.sole
    sign_in @adult.user
    with_intake { delete intake_me_application_path(@registration.slug, application) }

    assert_not MembershipApplication.exists?(application.id)
  end

  test "adding a family member links them and applies" do
    sign_in @adult.user
    with_intake do
      post intake_me_members_path(@registration.slug), params: { member: { first_name: "Avery", last_name: "Lee", birthday: "2014-02-02", team_ids: [ @juniors.id ] } }
    end

    avery = Person.find_by!(first_name: "Avery")
    assert_includes @adult.wards, avery
    assert_equal [ @juniors ], avery.membership_applications.map(&:team)
  end

  test "adding the same name twice is refused on the screen" do
    sign_in @adult.user
    with_intake do
      assert_no_difference -> { Person.count } do
        post intake_me_members_path(@registration.slug), params: { member: { first_name: "Sam", last_name: "Lee", team_ids: [ @juniors.id ] } }
      end
    end

    assert_equal "Sam Lee is already on this sign-up.", flash[:alert]
  end

  test "a young person names a guardian, who confirms and is linked" do
    young = create_intake_person("Sky", "Park")
    entry = @registration.entries.create!(first_name: "Sky", last_name: "Park", person: young, verified_at: Time.current, facts: { "team_ids" => [ @juniors.id ] })
    Intake::Enrollment.new(entry).apply(young)
    sign_in young.user

    with_intake do
      get intake_me_path(@registration.slug)
      assert_match "Waiting for a guardian", response.body
      assert_enqueued_jobs 1, only: SendEmailJob do
        post intake_me_guardians_path(@registration.slug), params: { guardian: { first_name: "Robin", last_name: "Park" }, guardian_email: "robin@example.com" }
      end
    end
    assert_empty young.guardians

    row = entry.household_members.guardian.sole
    token = row.issue_token!
    delete destroy_user_session_path
    with_intake do
      get intake_guardian_confirmation_path(token: token)
      assert_match "Sky would like to join Juniors.", response.body
      post intake_guardian_confirmation_path, params: { token: token, password: "Password1!", password_confirmation: "Password1!" }
    end

    guardian = User.find_by!(email: "robin@example.com").person
    assert_equal [ guardian ], young.guardians.to_a
    assert_redirected_to intake_me_path(@registration.slug)
    follow_redirect!
    assert_match "Sky", response.body
  end
end
