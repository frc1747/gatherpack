require "test_helper"
require_relative "../../support/intake_world"

# The fixes from the branch review (tasks/103 review, findings 1 to 7 and 11).
class Intake::ReviewFixesTest < ActionDispatch::IntegrationTest
  include IntakeWorld
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    build_intake_world
    @admin_badge = Badge.create!(name: "Admin Only", short: "AO", color: "red", badge_type: badge_types(:one), permission: "added_by_admin")
  end

  def verified_entry(person, teams: [ @juniors ], registration: @registration)
    registration.entries.create!(first_name: person.first_name, last_name: person.last_name, person: person,
      verified_at: Time.current, facts: { "team_ids" => teams.map(&:id) })
  end

  # 1. Badges

  test "a manager can only put badges they may give on a registration" do
    sign_in @leader.user
    with_intake do
      get edit_intake_registration_path(@registration)
      assert_select "select[name='intake_registration[badge_ids][]'] option", text: "Admin Only", count: 0
      patch intake_registration_path(@registration), params: { intake_registration: { badge_ids: [ @joined_badge.id, @admin_badge.id ] } }
    end

    assert_equal [ @joined_badge ], @registration.reload.badges.to_a
  end

  test "a manager's edit keeps a badge an admin put there" do
    @registration.update!(badge_ids: [ @joined_badge.id, @admin_badge.id ])
    sign_in @leader.user
    with_intake { patch intake_registration_path(@registration), params: { intake_registration: { title: "Join us", badge_ids: [ "" ] } } }

    assert_equal [ @admin_badge ], @registration.reload.badges.to_a
  end

  test "a manager's approval never gives a badge only admins may give" do
    @registration.update!(badge_ids: [ @joined_badge.id, @admin_badge.id ])
    applicant = create_intake_person("Riley", "Rivera", birthday: 30.years.ago.to_date)
    application = MembershipApplication.create!(person: applicant, team: @juniors, registration: @registration, source: :link)
    sign_in @leader.user

    with_intake { patch team_membership_application_path(@juniors, application), params: { status: "approved", pick_team_id: @class_2031.id } }

    assert application.reload.approved?
    assert_equal [ "Joined Online" ], applicant.badges.pluck(:name)
  end

  # 2. Staff-only details

  test "an applicant's own applications page shows no match or placement" do
    Person.create!(first_name: "Riley", last_name: "Rivera")
    applicant = create_intake_person("Riley", "Rivera", birthday: 30.years.ago.to_date)
    entry = verified_entry(applicant)
    Intake::Enrollment.new(entry).applicant_member!(applicant)
    Intake::Enrollment.new(entry).apply(applicant)
    sign_in applicant.user

    with_intake { get person_membership_applications_path(applicant) }

    assert_response :success
    assert_match "Registration link: Join Northwind", response.body
    assert_no_match "Might be the same person", response.body
    assert_no_match "Will also join", response.body
    assert_no_match "Deny with reason", response.body
  end

  # 3. Me writes

  test "nothing can be added on a closed registration" do
    adult = create_intake_person("Morgan", "Lee", birthday: 40.years.ago.to_date)
    verified_entry(adult)
    @registration.update!(closes_at: 1.minute.ago)
    sign_in adult.user

    with_intake do
      assert_no_difference -> { Person.count + Relationship.count + MembershipApplication.count } do
        post intake_me_members_path(@registration.slug), params: { member: { first_name: "Sam", last_name: "Lee", team_ids: [ @volunteers.id ] } }
      end
    end
    assert_equal "This registration is closed.", flash[:alert]
  end

  test "a kiosk-only registration takes changes only from people who signed up through it" do
    @registration.update!(self_service: false, kiosk: true)
    outsider = create_intake_person("Pat", "Outside", birthday: 40.years.ago.to_date)
    sign_in outsider.user

    with_intake do
      assert_no_difference -> { Person.count } do
        post intake_me_members_path(@registration.slug), params: { member: { first_name: "Sam", last_name: "Outside", team_ids: [ @juniors.id ] } }
      end
    end
    assert_equal "This registration is closed.", flash[:alert]
  end

  test "someone who needs a guardian can't add family members" do
    young = create_intake_person("Sky", "Park")
    verified_entry(young)
    sign_in young.user

    with_intake do
      assert_no_difference -> { Person.count + Relationship.count } do
        post intake_me_members_path(@registration.slug), params: { member: { first_name: "Kit", last_name: "Park", team_ids: [ @volunteers.id ] } }
      end
    end
    assert_equal "Ask a guardian to add family members.", flash[:alert]
  end

  test "an adult can't name a guardian" do
    adult = create_intake_person("Morgan", "Lee", birthday: 40.years.ago.to_date)
    Intake::Enrollment.new(verified_entry(adult)).apply(adult)
    sign_in adult.user

    with_intake do
      assert_no_enqueued_jobs only: Intake::GuardianEmailJob do
        post intake_me_guardians_path(@registration.slug), params: { guardian: { first_name: "A", last_name: "B" }, guardian_email: "x@example.com" }
      end
    end
  end

  # 4. Guardian requests

  test "one guardian request waits at a time" do
    young = create_intake_person("Sky", "Park")
    Intake::Enrollment.new(verified_entry(young)).apply(young)
    sign_in young.user

    with_intake do
      assert_enqueued_jobs 1, only: Intake::GuardianEmailJob do
        3.times do |i|
          post intake_me_guardians_path(@registration.slug), params: { guardian: { first_name: "G#{i}", last_name: "Park" }, guardian_email: "g#{i}@example.com" }
        end
      end
    end
    assert_match "already waiting for G0", flash[:alert]
  end

  test "guardian requests are limited per person per day" do
    young = create_intake_person("Sky", "Park")
    Intake::Enrollment.new(verified_entry(young)).apply(young)
    sign_in young.user

    with_intake(intake_rate_resend_per_day: "1") do
      post intake_me_guardians_path(@registration.slug), params: { guardian: { first_name: "Robin", last_name: "Park" }, guardian_email: "not-an-email" }
      post intake_me_guardians_path(@registration.slug), params: { guardian: { first_name: "Robin", last_name: "Park" }, guardian_email: "robin@example.com" }
    end
    assert_equal "Try again in a few minutes.", flash[:alert]
    assert_empty Intake::HouseholdMember.guardian
  end

  test "adding family members is limited per person per day" do
    adult = create_intake_person("Morgan", "Lee", birthday: 40.years.ago.to_date)
    verified_entry(adult)
    sign_in adult.user

    with_intake(intake_rate_household_per_day: "2") do
      %w[Ann Bea Cal].each do |first|
        post intake_me_members_path(@registration.slug), params: { member: { first_name: first, last_name: "Lee", team_ids: [ @juniors.id ] } }
      end
    end
    assert_equal 2, adult.wards.count
  end

  # 5. Own email as guardian

  test "naming your own email as your guardian is refused" do
    young = create_intake_person("Sky", "Park", email: "sky@example.com")
    Intake::Enrollment.new(verified_entry(young)).apply(young)
    sign_in young.user

    with_intake { post intake_me_guardians_path(@registration.slug), params: { guardian: { first_name: "Sky", last_name: "Park" }, guardian_email: " SKY@example.com" } }

    assert_equal "Enter your guardian's own email, not yours.", flash[:alert]
    assert_empty Intake::HouseholdMember.guardian
  end

  test "a young person opening their own guardian link confirms nothing" do
    young = create_intake_person("Sky", "Park", email: "sky@example.com")
    entry = verified_entry(young)
    row = entry.household_members.create!(role: :guardian, facts: { "ward_id" => young.id, "first_name" => "Sky", "last_name" => "Park", "email" => "sky@example.com" })
    token = row.issue_token!

    with_intake { post intake_guardian_confirmation_path, params: { token: token } }

    assert_response :unprocessable_content
    assert_nil row.reload.guardian_confirmed_at
    assert_empty young.guardians
  end

  # 6. Birthday

  test "a birthday on file isn't changed here" do
    adult = create_intake_person("Morgan", "Lee", birthday: 40.years.ago.to_date)
    verified_entry(adult)
    sign_in adult.user

    with_intake { patch intake_me_person_path(@registration.slug, adult), params: { person: { birthday: "1990-01-01" } } }

    assert_equal 40.years.ago.to_date, adult.reload.birthday
  end

  test "the birthday field's write level decides who adds one" do
    PersonField.ensure_system_fields!
    PersonField.find_by!(system_source: "birthday").update!(write_permission: "admin")
    young = create_intake_person("Sky", "Park")
    verified_entry(young)
    sign_in young.user

    with_intake { patch intake_me_person_path(@registration.slug, young), params: { person: { birthday: "1990-01-01" } } }

    assert_nil young.reload.birthday
    assert_equal "You can't add this birthday. Ask a leader.", flash[:alert]
  end

  # 7. Smaller ones

  test "sending again doesn't put the entry's name in the flash" do
    entry, = create_intake_entry(first_name: "Riley")
    sign_in @leader.user
    with_intake { post resend_intake_registration_entry_path(@registration, entry) }

    assert_equal "Sent again.", flash[:notice]
  end

  test "the spam page is off with the feature" do
    applicant = create_intake_person("Spam", "Bot")
    MembershipApplication.create!(person: applicant, team: @juniors, registration: @registration).deny!
    sign_in @admin.user
    delete intake_spam_person_path(applicant)

    assert_redirected_to root_path
    assert Person.exists?(applicant.id)
  end

  test "a successor must be a registration the editor can see" do
    other = Intake::Registration.create!(team: @juniors, title: "Juniors only", opens_at: 1.day.from_now, apply_team_ids: [ @juniors.id ])
    other.update_column(:team_id, Team.create!(name: "Elsewhere", team_type: team_types(:one)).id)
    sign_in @juniors_leader.user
    mine = Intake::Registration.create!(team: @juniors, title: "Mine", opens_at: 1.day.from_now, apply_team_ids: [ @juniors.id ])

    with_intake { patch intake_registration_path(mine), params: { intake_registration: { successor_id: other.id } } }

    assert_nil mine.reload.successor_id
  end

  # 11. Flag off

  test "with the feature off, approval runs no placement and sends no notice" do
    applicant = create_intake_person("Riley", "Rivera", birthday: 30.years.ago.to_date)
    application = MembershipApplication.create!(person: applicant, team: @juniors, registration: @registration, source: :link)

    assert_no_enqueued_jobs(only: SendEmailJob) { application.approve! }

    assert_equal [ "Juniors" ], applicant.teams.pluck(:name)
    assert_empty applicant.badges
  end
end
