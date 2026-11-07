require "test_helper"
require_relative "../../support/intake_world"

class Intake::PlacementTest < ActiveSupport::TestCase
  include IntakeWorld
  include ActiveJob::TestHelper

  setup do
    build_intake_world
    @applicant = create_intake_person("Riley", "Rivera", birthday: 30.years.ago.to_date)
    @application = MembershipApplication.create!(person: @applicant, team: @juniors, registration: @registration, source: :link)
  end

  test "approval adds the also-add teams, the badges and the pick, in the same step" do
    with_intake do
      @application.intake_pick_team = @class_2031
      @application.approve!
    end

    assert @application.reload.approved?
    assert_equal [ @class_2031, @everyone, @juniors ].map(&:name).sort, @applicant.teams.pluck(:name).sort
    assert_includes @applicant.badges, @joined_badge
    assert_equal [ "Everyone", "Class of 2031" ], @application.intake_placement[:teams]
  end

  test "placement is idempotent" do
    Membership.create!(person: @applicant, team: @everyone)
    placement = Intake::Placement.new(application: @application)

    first = placement.apply!
    second = placement.apply!

    assert_empty first[:teams]
    assert_equal [ "Joined Online" ], first[:badges]
    assert_equal({ teams: [], badges: [], guardian_teams: [] }, second)
    assert_equal 1, @applicant.memberships.where(team: @everyone).count
    assert_equal 1, @applicant.badge_assignments.where(badge: @joined_badge).count
  end

  test "a pick outside the pick-one list is ignored" do
    Intake::Placement.new(application: @application, pick_team: @mentors).apply!

    assert_not @applicant.teams.include?(@mentors)
  end

  test "a required pick is missing until one is chosen" do
    @registration.update!(pick_one_required: true)

    assert Intake::Placement.new(application: @application).missing_pick?
    assert_not Intake::Placement.new(application: @application, pick_team: @class_2032).missing_pick?
  end

  test "a pick is never required when the registration has no pick-one teams" do
    @registration.update!(pick_one_required: true, pick_one_team_ids: [])

    assert_not Intake::Placement.new(application: @application.reload).missing_pick?
  end

  test "guardians join the guardian teams on approval" do
    guardian = create_intake_person("Gale", "Rivera")
    young = Person.create!(first_name: "Sky", last_name: "Rivera", birthday: 12.years.ago.to_date)
    Relationship.new(relationship_type: @parent_of, parent: guardian, child: young).save!(validate: false)
    application = MembershipApplication.create!(person: young, team: @juniors, registration: @registration, source: :link)

    with_intake { application.approve! }

    assert_includes guardian.teams, @families
    assert_not young.teams.include?(@families)
  end

  test "the preview names what approval would add" do
    preview = Intake::Placement.new(application: @application).preview

    assert_equal [ "Everyone" ], preview[:teams]
    assert_equal [ "Joined Online" ], preview[:badges]
    assert_empty preview[:guardian_teams]
  end

  test "the pick is suggested from a field value matching a team's name" do
    field = PersonField.create!(name: "Graduation year", data_type: :string, read_permission: "admin", write_permission: "admin")
    @applicant.set_field_value(field.key, "2032")

    assert_equal @class_2032, Intake::Placement.new(application: @application.reload).suggested_pick
  end

  test "applications made without a registration approve as before" do
    application = MembershipApplication.create!(person: create_intake_person("Pat", "Plain"), team: @mentors)

    with_intake { application.approve! }

    assert application.reload.approved?
    assert application.source_request?
    assert_equal [ "Mentors" ], application.person.teams.pluck(:name)
  end

  test "a denial keeps the reason and tells the applicant" do
    with_intake do
      assert_enqueued_with(job: SendEmailJob) { @application.deny!("We're full this year.") }
    end

    assert @application.reload.denied?
    assert_equal "We're full this year.", @application.reviewer_notes
  end
end
