require "test_helper"
require_relative "../../support/intake_world"

class Intake::EnrollmentTest < ActiveSupport::TestCase
  include IntakeWorld

  setup do
    build_intake_world
    @adult = create_intake_person("Morgan", "Lee", birthday: 40.years.ago.to_date)
  end

  def verified_entry(person, teams: [ @juniors ])
    @registration.entries.create!(first_name: person.first_name, last_name: person.last_name, person: person,
      verified_at: Time.current, facts: { "team_ids" => teams.map(&:id) })
  end

  test "applying makes an application with the registration and source" do
    entry = verified_entry(@adult)
    applications = Intake::Enrollment.new(entry).apply(@adult)

    assert_equal 1, applications.size
    assert_equal @registration, applications.first.registration
    assert applications.first.source_link?
  end

  test "a team that needs no approval is joined at once, with placement" do
    entry = verified_entry(@adult, teams: [ @volunteers ])
    Intake::Enrollment.new(entry).apply(@adult)

    assert_includes @adult.teams, @volunteers
    assert_includes @adult.teams, @everyone
    assert_empty @adult.membership_applications
  end

  test "applying twice, or as a member, makes nothing new" do
    entry = verified_entry(@adult, teams: [ @juniors, @mentors ])
    Membership.create!(person: @adult, team: @mentors)
    enrollment = Intake::Enrollment.new(entry)

    enrollment.apply(@adult)
    enrollment.apply(@adult)

    assert_equal [ @juniors ], @adult.membership_applications.map(&:team)
  end

  test "teams outside the registration are ignored" do
    entry = verified_entry(@adult, teams: [ @juniors ])
    Intake::Enrollment.new(entry).apply(@adult, [ @families.id ])

    assert_empty @adult.membership_applications
    assert_not @adult.teams.include?(@families)
  end

  test "a family member is linked as the adder's ward and applies" do
    entry = verified_entry(@adult)
    ward = Intake::Enrollment.new(entry).add_ward(adder: @adult, first_name: "Sam", last_name: "Lee", birthday: 10.years.ago.to_date)

    assert_nil ward.user
    assert_includes @adult.wards, ward
    assert_equal [ @juniors ], ward.membership_applications.map(&:team)
    assert entry.household_members.ward.exists?(person: ward)
  end

  test "the same name twice in a household is refused" do
    entry = verified_entry(@adult)
    enrollment = Intake::Enrollment.new(entry)
    enrollment.add_ward(adder: @adult, first_name: "Sam", last_name: "Lee")

    error = assert_raises(Intake::Enrollment::Refused) { enrollment.add_ward(adder: @adult, first_name: " sam ", last_name: "LEE") }
    assert_match "already on this sign-up", error.message
    assert_raises(Intake::Enrollment::Refused) { enrollment.add_ward(adder: @adult, first_name: "Morgan", last_name: "Lee") }
  end

  test "no matching across households: a same-named child elsewhere is a new person, noted for staff only" do
    other_adult = create_intake_person("Jordan", "Lee", birthday: 41.years.ago.to_date)
    first = Intake::Enrollment.new(verified_entry(other_adult)).add_ward(adder: other_adult, first_name: "Sam", last_name: "Lee")

    entry = verified_entry(@adult)
    second = Intake::Enrollment.new(entry).add_ward(adder: @adult, first_name: "Sam", last_name: "Lee")

    assert_not_equal first, second
    assert_not_includes @adult.wards, first
    assert_not_includes other_adult.wards, second
    assert_equal first, entry.household_members.find_by(person: second).possible_match
  end

  test "a name match is only with people who have no login" do
    create_intake_person("Casey", "Quinn")
    placeholder = Person.create!(first_name: "Casey", last_name: "Quinn")

    assert_equal placeholder, Intake.possible_match(first_name: "casey", last_name: "quinn ")
    assert_nil Intake.possible_match(first_name: "Casey", last_name: "Quinn", except: placeholder.id)
  end

  test "a birthday narrows a name match when both are known" do
    Person.create!(first_name: "Casey", last_name: "Quinn", birthday: Date.new(2012, 3, 4))

    assert_nil Intake.possible_match(first_name: "Casey", last_name: "Quinn", birthday: Date.new(2013, 1, 1))
    assert Intake.possible_match(first_name: "Casey", last_name: "Quinn", birthday: Date.new(2012, 3, 4))
  end

  test "login emails match trimmed and case-insensitively" do
    assert_equal @adult.user, Intake.user_for_email("  #{@adult.user.email.upcase} ")
    assert_nil Intake.user_for_email("nobody@example.com")
  end

  test "a guardian is linked only when they confirm" do
    young = create_intake_person("Sky", "Park")
    entry = verified_entry(young)
    enrollment = Intake::Enrollment.new(entry)
    row, token = enrollment.name_guardian(ward: young, first_name: "Robin", last_name: "Park", email: "Robin.Park@example.com")

    assert_empty young.guardians
    assert_equal row, Intake::HouseholdMember.find_guardian_by_token(token)

    guardian = create_intake_person("Robin", "Park", email: "robin.park@example.com")
    enrollment.confirm_guardian(row, guardian)

    assert_equal [ guardian ], young.guardians.to_a
    assert row.reload.guardian_confirmed_at
    assert_nil Intake::HouseholdMember.find_guardian_by_token(token)
  end
end
