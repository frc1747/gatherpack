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

  # 8. Lists keep what the editor can't manage

  test "a manager's edit keeps teams an admin added outside their tree" do
    shared = Team.create!(name: "Shared Families", team_type: team_types(:one))
    @registration.update!(guardian_also_add_team_ids: [ @families.id, shared.id ], apply_team_ids: [ @juniors.id, @mentors.id, shared.id ])
    sign_in @leader.user

    with_intake do
      patch intake_registration_path(@registration), params: { intake_registration: { title: "Join us",
        apply_team_ids: [ "", @juniors.id ], guardian_also_add_team_ids: [ "", @families.id ] } }
    end

    @registration.reload
    assert_equal [ @juniors.id, shared.id ].sort, @registration.apply_team_ids.sort
    assert_equal [ @families.id, shared.id ].sort, @registration.guardian_also_add_team_ids.sort
  end

  # 9. Signed-in join with no team

  test "signed in, joining with no team checked shows the form again" do
    person = create_intake_person("Casey", "Quinn", birthday: 30.years.ago.to_date)
    sign_in person.user

    with_intake { post intake_join_path(@registration.slug), params: { entry: { team_ids: [ "" ] } } }

    assert_response :unprocessable_content
    assert_select ".alert-danger", "Choose at least one team."
    assert_empty Intake::Entry.all
  end

  # 10. One "closed" hook

  test "close now fires the closed hook once, from the hourly job" do
    Hook.create!(name: "Closed", event: "intake_registrations - closed", code: "(Thread.current[:intake_hooks] ||= []) << 'closed'")
    sign_in @leader.user

    with_intake do
      patch close_intake_registration_path(@registration)
      patch close_intake_registration_path(@registration)
      Intake::RegistrationDatesJob.perform_now(1.minute.from_now)
    end

    assert_equal %w[closed], Thread.current[:intake_hooks]
  ensure
    Thread.current[:intake_hooks] = nil
  end

  # Re-review 2. Linking a guardian on file

  def young_applicant(first, registration: @registration, team: @juniors)
    young = Person.create!(first_name: first, last_name: "Park", birthday: 12.years.ago.to_date)
    MembershipApplication.create!(person: young, team: team, registration: registration, source: :kiosk)
    young
  end

  test "a guardian can't be linked to an applicant who doesn't need one" do
    adult = create_intake_person("Ada", "Grown", birthday: 40.years.ago.to_date)
    MembershipApplication.create!(person: adult, team: @juniors, registration: @registration, source: :link)
    robin = create_intake_person("Robin", "Park")
    sign_in @leader.user

    with_intake { post intake_registration_guardians_path(@registration), params: { ward_id: adult.id, guardian: robin.neat_id } }

    assert_equal "Ada doesn't need a guardian linked.", flash[:alert]
    assert_empty adult.guardians
  end

  test "a manager can't link themselves as a guardian" do
    young = young_applicant("Sky")
    sign_in @leader.user

    with_intake { post intake_registration_guardians_path(@registration), params: { ward_id: young.id, guardian: @leader.user.email } }

    assert_match "it's you or a relative", flash[:alert]
    assert_empty young.guardians
  end

  test "a request from another registration, or for another young person, can't be used" do
    other_registration = Intake::Registration.create!(team: @mentors, title: "Mentors", opens_at: 1.day.ago, apply_team_ids: [ @mentors.id ],
      guardian_relationship_type: @parent_of)
    their_kid = young_applicant("Kit", registration: other_registration, team: @mentors)
    entry = other_registration.entries.create!(first_name: "Kit", last_name: "Park", person: their_kid, verified_at: Time.current, facts: { "team_ids" => [ @mentors.id ] })
    foreign_row = Intake::Enrollment.new(entry).name_guardian(ward: their_kid, first_name: "Robin", last_name: "Park", email: "robin@example.com")
    mine = young_applicant("Sky")
    robin = create_intake_person("Robin", "Park")
    sign_in @juniors_leader.user
    Intake::Registration.where(id: @registration.id).update_all(team_id: @juniors.id)

    with_intake { post intake_registration_guardians_path(@registration), params: { ward_id: mine.id, row_id: foreign_row.id, guardian: robin.neat_id } }
    assert_response :not_found

    own_entry = @registration.entries.create!(first_name: "Sky", last_name: "Park", person: mine, verified_at: Time.current, facts: { "team_ids" => [ @juniors.id ] })
    other_young = young_applicant("Lu")
    row = Intake::Enrollment.new(own_entry).name_guardian(ward: mine, first_name: "Robin", last_name: "Park", email: "robin2@example.com")
    sign_in @juniors_leader.user # a 404 response doesn't keep the test's session
    with_intake { post intake_registration_guardians_path(@registration), params: { ward_id: other_young.id, row_id: row.id, guardian: robin.neat_id } }
    assert_response :not_found

    assert_empty their_kid.guardians
    assert_empty other_young.guardians
  end

  # Re-review 3. Badges on joins that need no approval

  test "joining a team that needs no approval gives only badges the joiner could give" do
    @registration.update!(badge_ids: [ @joined_badge.id, @admin_badge.id ])
    member = create_intake_person("Pat", "Joiner", birthday: 30.years.ago.to_date)
    sign_in member.user

    with_intake { post intake_join_path(@registration.slug), params: { entry: { team_ids: [ @volunteers.id ] } } }

    assert_includes member.teams, @volunteers
    assert_equal [ "Joined Online" ], member.badges.pluck(:name)
  end

  test "a family member joining a team that needs no approval gets only badges their adder could give" do
    @registration.update!(badge_ids: [ @admin_badge.id ])
    adult = create_intake_person("Morgan", "Lee", birthday: 40.years.ago.to_date)
    ward = with_intake { Intake::Enrollment.new(verified_entry(adult)).add_ward(adder: adult, first_name: "Sam", last_name: "Lee", teams: [ @volunteers.id ]) }

    assert_includes ward.teams, @volunteers
    assert_empty ward.badges
  end

  # Re-review 5. No confirmed guardian without a tie

  test "a guardian link can't be confirmed once the registration stops linking guardians" do
    young = create_intake_person("Sky", "Park")
    entry = verified_entry(young)
    row = Intake::Enrollment.new(entry).name_guardian(ward: young, first_name: "Robin", last_name: "Park", email: "robin@example.com")
    token = row.issue_token!
    @registration.update!(guardian_relationship_type: nil)

    with_intake do
      get intake_guardian_confirmation_path(token: token)
      assert_response :unprocessable_content
      post intake_guardian_confirmation_path, params: { token: token, password: "Password1!", password_confirmation: "Password1!" }
    end

    assert_response :unprocessable_content
    assert_nil row.reload.guardian_confirmed_at
    assert_nil User.find_by(email: "robin@example.com")
  end

  test "confirming a guardian without a guardianship type is refused" do
    young = create_intake_person("Sky", "Park")
    entry = verified_entry(young)
    row = Intake::Enrollment.new(entry).name_guardian(ward: young, first_name: "Robin", last_name: "Park", email: "robin@example.com")
    @registration.update!(guardian_relationship_type: nil)
    robin = create_intake_person("Robin", "Park")

    assert_raises(Intake::Enrollment::Refused) { Intake::Enrollment.new(entry.reload).confirm_guardian(row, robin) }
    assert_nil row.reload.guardian_confirmed_at
  end
end
