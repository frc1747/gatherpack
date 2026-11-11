require "test_helper"
require_relative "../../support/intake_world"

class Intake::DecisionsAndKioskTeamTest < ActionDispatch::IntegrationTest
  include IntakeWorld
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    build_intake_world
  end

  test "nobody approves their own application" do
    application = MembershipApplication.create!(person: @leader, team: @juniors, registration: @registration, source: :kiosk)
    sign_in @leader.user

    with_intake { patch team_membership_application_path(@juniors, application), params: { status: "approved" } }

    assert application.reload.pending?
    assert_equal "You can't decide your own application or a relative's.", flash[:alert]
  end

  test "nobody decides a relative's application, admins included" do
    ward = Person.create!(first_name: "Kit", last_name: "Admin", birthday: 10.years.ago.to_date)
    Relationship.new(relationship_type: @parent_of, parent: @admin, child: ward).save!(validate: false)
    application = MembershipApplication.create!(person: ward, team: @juniors, registration: @registration, source: :kiosk)
    sign_in @admin.user

    with_intake do
      patch team_membership_application_path(@juniors, application), params: { status: "denied" }
      get applications_team_path(@juniors)
    end

    assert application.reload.pending?
    assert_match "Someone else decides this one", response.body
  end

  test "another manager decides it" do
    ward = Person.create!(first_name: "Kit", last_name: "Leader", birthday: 10.years.ago.to_date)
    Relationship.new(relationship_type: @parent_of, parent: @juniors_leader, child: ward).save!(validate: false)
    application = MembershipApplication.create!(person: ward, team: @juniors, registration: @registration, source: :kiosk)
    sign_in @leader.user

    with_intake { patch team_membership_application_path(@juniors, application), params: { status: "approved", pick_team_id: @class_2031.id } }

    assert application.reload.approved?
  end

  test "the approval stores what placement added and who approved" do
    applicant = create_intake_person("Riley", "Rivera", birthday: 30.years.ago.to_date)
    application = MembershipApplication.create!(person: applicant, team: @juniors, registration: @registration, source: :link)
    sign_in @leader.user

    with_intake do
      patch team_membership_application_path(@juniors, application), params: { status: "approved", pick_team_id: @class_2032.id }
      get person_membership_applications_path(applicant)
    end

    placement = application.reload.intake_placement
    assert_equal [ "Everyone", "Class of 2032" ], placement["teams"]
    assert_equal [ "Joined Online" ], placement["badges"]
    assert_equal @leader.id, placement["approved_by_id"]
    assert_match "Approval added to Everyone and Class of 2032; gave Joined Online.", response.body
    assert AuditLog.where(item_type: "MembershipApplication", item_id: application.id).any? { |version| version.object_changes.to_s.include?("intake_placement") }
  end

  test "the kiosk team is the one chosen by id, even when another has its name" do
    chosen = Team.create!(name: "Kiosks", team_type: team_types(:one))
    Team.create!(name: "Kiosks", team_type: team_types(:one))
    @registration.update!(kiosk: true)
    device = create_intake_person("Front", "Desk", team: chosen, manager: false)
    Membership.create!(person: device, team: @northwind, manager: true)
    sign_in device.user

    with_intake(intake_kiosk_users_team: chosen.id) { get intake_kiosk_path(@registration.slug) }
    assert_response :success
  end

  test "the time kiosk's team is used when the registration kiosk's is blank" do
    # The time kiosk's setting belongs to another feature; stand it in, in a throwaway store.
    with_settings({}) { Settings.register(:time_kiosk_users_team, :string, "Time kiosk team", "", "Time Clock", "") } unless Settings.get(:time_kiosk_users_team)
    kiosks = Team.create!(name: "Kiosks", team_type: team_types(:one))
    @registration.update!(kiosk: true)
    sign_in @leader.user

    with_intake(time_kiosk_users_team: kiosks.id) { get intake_kiosk_path(@registration.slug) }
    assert_redirected_to root_path

    Membership.create!(person: @leader, team: kiosks)
    with_intake(time_kiosk_users_team: kiosks.id) { get intake_kiosk_path(@registration.slug) }
    assert_response :success
  end

  test "the settings page offers the kiosk team as a team picker" do
    sign_in @admin.user
    get settings_path

    assert_select "select[name='settings[intake_kiosk_users_team]'] option", text: "Northwind"
  end
end
