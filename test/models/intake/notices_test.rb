require "test_helper"
require_relative "../../support/intake_world"

class Intake::NoticesTest < ActiveJob::TestCase
  include IntakeWorld

  setup do
    build_intake_world
    Membership.create!(person: @admin, team: @everyone)
  end

  def busy_addresses(settings = {})
    clear_enqueued_jobs
    with_intake(settings) { Intake::Notices.registration_busy(@registration) }
    enqueued_jobs.select { |job| job[:job] == SendEmailJob }.map { |job| job[:args].second }.sort
  end

  test "admins hear a registration is busy by default" do
    assert_equal [ @admin.user.email, @leader.user.email ].sort, busy_addresses
  end

  test "with admin notices off, only the team's managers hear a registration is busy" do
    assert_equal [ @leader.user.email ], busy_addresses(notices_admins_everywhere: "false")
  end

  test "with admin notices off, an admin who manages the team still hears" do
    Membership.create!(person: @admin, team: @northwind, manager: true)

    assert_equal [ @admin.user.email, @leader.user.email ].sort, busy_addresses(notices_admins_everywhere: "false")
  end

  test "with admin notices off, a team with no manager still reaches every admin" do
    @leader.memberships.destroy_all
    other = create_intake_person("Abe", "Admin", admin: true)

    assert_equal [ @admin.user.email, other.user.email ].sort, busy_addresses(notices_admins_everywhere: "false")
  end

  test "notice teams are the managed teams and those below, with nothing added for admins" do
    assert_empty @admin.notice_teams
    assert_equal [ @juniors ], @juniors_leader.notice_teams.to_a
    assert_includes @leader.notice_teams, @mentors
  end

  test "admins keep every permission with admin notices off" do
    application = MembershipApplication.create!(person: Person.create!(first_name: "Ann", last_name: "Lee"), team: @juniors, registration: @registration)

    with_intake(notices_admins_everywhere: "false") do
      assert_equal Team.count, @admin.all_managed_teams.count
      assert_includes Intake::RegistrationPolicy::Scope.new(@admin.user, Intake::Registration).resolve, @registration
      assert Intake::RegistrationPolicy.new(@admin.user, @registration).show?
      assert MembershipApplicationPolicy.new(@admin.user, application).update?
    end
  end
end
