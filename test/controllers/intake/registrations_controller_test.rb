require "test_helper"
require_relative "../../support/intake_world"

class Intake::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  include IntakeWorld
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    build_intake_world
  end

  test "a manager sees and creates registrations for their teams" do
    sign_in @leader.user
    with_intake do
      get intake_registrations_path
      assert_response :success
      assert_match "Join Northwind", response.body

      assert_difference -> { Intake::Registration.count } do
        post intake_registrations_path, params: { intake_registration: { team_id: @northwind.id, title: "Mentors", opens_at: "2026-12-01T09:00",
          apply_team_ids: [ "", @mentors.id ], also_add_team_ids: [ @everyone.id ], badge_ids: [ "", @joined_badge.id ] } }
      end
    end

    registration = Intake::Registration.find_by!(title: "Mentors")
    assert_redirected_to intake_registration_path(registration)
    assert_equal [ @mentors.id ], registration.apply_team_ids
    assert_equal [ @everyone.id ], registration.also_add_team_ids
    assert_equal @leader, registration.created_by
  end

  test "team lists keep only teams the person manages" do
    sign_in @juniors_leader.user
    with_intake do
      post intake_registrations_path, params: { intake_registration: { team_id: @juniors.id, title: "Juniors", opens_at: "2026-12-01T09:00",
        apply_team_ids: [ @juniors.id, @mentors.id ] } }
    end

    assert_equal [ @juniors.id ], Intake::Registration.find_by!(title: "Juniors").apply_team_ids
  end

  test "a manager of another team can't see or change a registration" do
    sign_in @juniors_leader.user
    with_intake do
      get intake_registration_path(@registration)
      assert_response :not_found
      get intake_registrations_path
      assert_no_match "Join Northwind", response.body
    end
  end

  test "someone who manages nothing can't open registrations" do
    member = create_intake_person("Pat", "Member", team: @everyone)
    sign_in member.user
    with_intake { get intake_registrations_path }

    assert_redirected_to root_path
  end

  test "the entries screen shows unfinished sign-ups and deletes selected ones" do
    keep, = create_intake_entry(first_name: "Keep", email: "keep@example.com")
    drop, = create_intake_entry(first_name: "Drop", email: "drop@example.com")
    sign_in @leader.user

    with_intake do
      get intake_registration_path(@registration)
      assert_match "Keep", response.body
      assert_match "No bot check", response.body
      assert_no_match "keep@example.com", response.body
      delete entries_intake_registration_path(@registration), params: { entry_ids: [ drop.id ] }
    end

    assert Intake::Entry.exists?(keep.id)
    assert_not Intake::Entry.exists?(drop.id)
  end

  test "the entries screen counts sign-ups by local day" do
    with_settings(time_zone: "Eastern Time (US & Canada)") do
      travel_to(Time.utc(2026, 11, 5, 15)) do
        entry, = create_intake_entry
        entry.update_columns(created_at: Time.utc(2026, 11, 6, 2))
        sign_in @leader.user

        with_intake { get intake_registration_path(@registration) }

        assert_match "<td>November 05, 2026</td>", response.body
        assert_no_match "<td>November 06, 2026</td>", response.body
      end
    end
  end

  test "close now ends the registration" do
    sign_in @leader.user
    with_intake { patch close_intake_registration_path(@registration) }

    assert @registration.reload.closed?
  end

  test "sending again is limited per sign-up per day" do
    entry, = create_intake_entry
    sign_in @leader.user

    with_intake(intake_rate_resend_per_day: "1") do
      assert_enqueued_jobs 1, only: Intake::EntryEmailJob do
        2.times { post resend_intake_registration_entry_path(@registration, entry) }
      end
    end
    assert_match "too often", flash[:alert]
  end

  test "copy proposes the next dates for a person to confirm" do
    sign_in @leader.user
    with_intake { get copy_intake_registration_path(@registration) }

    assert_response :success
    assert_select "input[name='intake_registration[title]'][value='Join Northwind']"
  end

  test "switched off, the staff screens are hidden" do
    sign_in @leader.user
    get intake_registrations_path

    assert_redirected_to root_path
  end
end
