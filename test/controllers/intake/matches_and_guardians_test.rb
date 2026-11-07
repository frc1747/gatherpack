require "test_helper"
require_relative "../../support/intake_world"

class Intake::MatchesAndGuardiansTest < ActionDispatch::IntegrationTest
  include IntakeWorld
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    build_intake_world
    @placeholder = Person.create!(first_name: "Riley", last_name: "Rivera")
    @riley = create_intake_person("Riley", "Rivera", email: "riley@example.com", birthday: 30.years.ago.to_date)
    @entry = @registration.entries.create!(first_name: "Riley", last_name: "Rivera", person: @riley, verified_at: Time.current,
      facts: { "team_ids" => [ @juniors.id ] })
    @member = Intake::Enrollment.new(@entry).applicant_member!(@riley)
    Intake::Enrollment.new(@entry).apply(@riley)
    sign_in @leader.user
  end

  test "managers see the possible match with Link and Keep separate" do
    with_intake { get applications_team_path(@juniors) }

    assert_match "Might be the same person as", response.body
    assert_select "form[action='#{link_intake_registration_match_path(@registration, @member)}']"
    assert_select "form[action='#{keep_separate_intake_registration_match_path(@registration, @member)}']"
  end

  test "Link attaches the sign-up, application and login to the person on file" do
    login = @riley.user
    with_intake { post link_intake_registration_match_path(@registration, @member) }

    assert_equal "Linked to Riley Rivera.", flash[:notice]
    assert_not Person.exists?(@riley.id)
    @placeholder.reload
    assert_equal login, @placeholder.user
    assert_equal [ @juniors ], @placeholder.membership_applications.map(&:team)
    assert_equal @placeholder, @entry.reload.person
    assert_equal @placeholder, @member.reload.person
    assert_nil @member.possible_match
    assert_equal 30.years.ago.to_date, @placeholder.birthday
  end

  test "Link moves a ward's guardian tie" do
    kid_on_file = Person.create!(first_name: "Sam", last_name: "Rivera")
    ward = Intake::Enrollment.new(@entry).add_ward(adder: @riley, first_name: "Sam", last_name: "Rivera", teams: [ @juniors.id ])
    ward_row = @entry.household_members.find_by!(person: ward)
    assert_equal kid_on_file, ward_row.possible_match

    with_intake { post link_intake_registration_match_path(@registration, ward_row) }

    assert_includes @riley.wards, kid_on_file
    assert_equal [ @juniors ], kid_on_file.membership_applications.map(&:team)
    assert_not Person.exists?(ward.id)
  end

  test "Link is refused when the new person has other records" do
    Membership.create!(person: @riley, team: @everyone)
    with_intake { post link_intake_registration_match_path(@registration, @member) }

    assert_match "has other records", flash[:alert]
    assert Person.exists?(@riley.id)
  end

  test "Keep separate clears the flag" do
    with_intake { post keep_separate_intake_registration_match_path(@registration, @member) }

    assert_nil @member.reload.possible_match
    assert_equal @placeholder.id, @member.facts["kept_separate_from_id"]
    assert Person.exists?(@riley.id)
  end

  test "another team's manager can't link" do
    sign_in @juniors_leader.user
    with_intake { post link_intake_registration_match_path(@registration, @member) }

    assert_response :not_found
    assert Person.exists?(@riley.id)
  end

  def young_with_request
    young = create_intake_person("Sky", "Park")
    entry = @registration.entries.create!(first_name: "Sky", last_name: "Park", person: young, verified_at: Time.current, facts: { "team_ids" => [ @juniors.id ] })
    Intake::Enrollment.new(entry).apply(young)
    row = Intake::Enrollment.new(entry).name_guardian(ward: young, first_name: "Robin", last_name: "Park", email: "robin@exampel.com")
    [ young, row ]
  end

  test "a manager corrects a guardian's email, which sends a new request there" do
    young, row = young_with_request
    old_token = row.issue_token!

    sent = with_intake do
      capture_intake_mail do
        patch intake_registration_guardian_path(@registration, row), params: { email: "robin@example.com" }
        perform_enqueued_jobs(only: Intake::GuardianEmailJob)
      end
    end

    assert_equal "robin@example.com", row.reload.facts["email"]
    assert_nil Intake::HouseholdMember.find_guardian_by_token(old_token)
    assert_equal [ "robin@example.com" ], sent.map(&:first)
    assert_empty young.guardians
  end

  test "a corrected email can't be the young person's own" do
    young, row = young_with_request
    with_intake { patch intake_registration_guardian_path(@registration, row), params: { email: young.user.email } }

    assert_match "own email", flash[:alert]
    assert_equal "robin@exampel.com", row.reload.facts["email"]
  end

  test "Send again goes to the guardian, a few times a day" do
    _, row = young_with_request

    with_intake(intake_rate_resend_per_day: "1") do
      assert_enqueued_with(job: Intake::GuardianEmailJob, args: [ row.id ]) do
        post resend_intake_registration_guardian_path(@registration, row)
      end
      post resend_intake_registration_guardian_path(@registration, row)
    end
    assert_match "too often", flash[:alert]
  end

  test "a manager links a guardian already on file, by login email or id" do
    young, row = young_with_request
    robin = create_intake_person("Robin", "Park", email: "robin.park@example.com")

    with_intake { post intake_registration_guardians_path(@registration), params: { ward_id: young.id, row_id: row.id, guardian: "ROBIN.PARK@example.com" } }

    assert_equal [ robin ], young.guardians.to_a
    assert_equal @leader.id, row.reload.facts["linked_by_id"]
    with_intake { get applications_team_path(@juniors) }
    assert_match "linked by Lena Leader", response.body

    other = Person.create!(first_name: "Kit", last_name: "Park", birthday: 12.years.ago.to_date)
    MembershipApplication.create!(person: other, team: @juniors, registration: @registration, source: :kiosk)
    with_intake { post intake_registration_guardians_path(@registration), params: { ward_id: other.id, guardian: robin.neat_id } }
    assert_includes robin.wards, other
  end

  test "guardians can only be linked to the registration's applicants" do
    stranger = Person.create!(first_name: "Not", last_name: "Applying")
    robin = create_intake_person("Robin", "Park")

    with_intake { post intake_registration_guardians_path(@registration), params: { ward_id: stranger.id, guardian: robin.neat_id } }

    assert_response :not_found
    assert_empty stranger.guardians
  end
end
