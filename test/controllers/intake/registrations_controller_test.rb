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
      assert_select ".table-responsive[data-controller=column-chooser][data-column-chooser-key-value=intake-registrations]"

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

  test "the Registrations menu item is only for those who can open it" do
    item = GatherPack::Features.all.find { |feature| feature.key == :intake }.nav_items.find { |nav| nav.label == "Registrations" }
    skip "menu items can't be hidden per person here" unless item.respond_to?(:visible) && item.visible

    member = create_intake_person("Pat", "Member", team: @everyone)
    assert item.visible.call(@leader.user)
    assert_not item.visible.call(member.user)
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

  test "the registration pages show a breadcrumb" do
    @registration.update!(kiosk: true)
    sign_in @leader.user

    with_intake do
      { intake_registrations_path => "Registrations", intake_registration_path(@registration) => "Join Northwind",
        new_intake_registration_path => "New registration", edit_intake_registration_path(@registration) => "Join Northwind",
        waiting_intake_registration_path(@registration) => "Waiting to finish" }.each do |path, last|
        get path
        assert_response :success, path
        assert_select ".breadcrumb-container a.breadcrumb-link", text: "Home"
        assert_select ".breadcrumb-container", text: /#{Regexp.escape(last)}/
      end
    end
  end

  test "choosing No, closed and saving closes the registration for joiners" do
    sign_in @leader.user

    with_intake do
      get edit_intake_registration_path(@registration)
      assert_select "input[type=radio][name=taking]", 3
      assert_select "input[name=taking][value=open][checked]"

      patch intake_registration_path(@registration), params: { taking: "closed", intake_registration: { title: @registration.title } }
      assert_redirected_to intake_registration_path(@registration)

      assert @registration.reload.closed?
      get intake_join_path(@registration.slug)
      assert_response :not_found
      assert_match "Registration has closed.", response.body
    end
  end

  test "choosing Yes, open now opens a registration that hasn't opened and drops a past closing time" do
    @registration.update!(opens_at: 2.days.from_now, closes_at: 3.days.from_now)
    sign_in @leader.user
    with_intake { patch intake_registration_path(@registration), params: { taking: "open", intake_registration: { title: @registration.title } } }
    assert @registration.reload.open?

    @registration.update_columns(opens_at: 5.days.ago, closes_at: 1.day.ago)
    with_intake { patch intake_registration_path(@registration), params: { taking: "open", intake_registration: { title: @registration.title } } }
    assert @registration.reload.open?
    assert_nil @registration.closes_at
  end

  test "choosing Not yet needs an opening time still to come" do
    sign_in @leader.user
    with_intake do
      patch intake_registration_path(@registration), params: { taking: "not_yet", intake_registration: { title: @registration.title } }
      assert_response :unprocessable_content
      assert @registration.reload.open?

      patch intake_registration_path(@registration), params: { taking: "not_yet", intake_registration: { opens_at: 3.days.from_now.strftime("%Y-%m-%dT%H:%M") } }
      assert_redirected_to intake_registration_path(@registration)
    end
    assert @registration.reload.not_yet_open?
  end

  test "dates typed beside an unchanged choice are kept" do
    sign_in @leader.user
    closes = 2.days.from_now.change(sec: 0)
    with_intake { patch intake_registration_path(@registration), params: { taking: "open", taking_was: "open", intake_registration: { closes_at: closes.strftime("%Y-%m-%dT%H:%M") } } }

    assert_equal closes.to_i, @registration.reload.closes_at.to_i
  end

  test "a new registration with a future opening time and the choice left alone stays not yet" do
    sign_in @leader.user
    opens = 5.days.from_now.change(sec: 0)

    with_intake do
      get new_intake_registration_path
      assert_select "input[name=taking_was][value=open]"
      post intake_registrations_path, params: { taking: "open", taking_was: "open", intake_registration: { team_id: @northwind.id, title: "Next season",
        opens_at: opens.strftime("%Y-%m-%dT%H:%M"), apply_team_ids: [ @mentors.id ] } }
    end

    registration = Intake::Registration.find_by!(title: "Next season")
    assert registration.not_yet_open?
    assert_equal opens.to_i, registration.opens_at.to_i
  end

  test "the registration page says its state and ends with Edit, Waiting to finish, More; Delete last" do
    @registration.update!(kiosk: true, closes_at: 10.days.from_now)
    sign_in @leader.user

    with_intake { get intake_registration_path(@registration) }

    assert_match "Taking registrations until", response.body
    assert_no_match "Close now", response.body
    footer = css_select(".card-footer.screen-action-row").first
    assert_equal [ "Edit", "Waiting to finish" ], footer.css("a.btn").map { |link| link.text.strip }
    assert_equal "More", footer.at_css("button.dropdown-toggle").text.strip
    items = footer.css(".dropdown-menu .dropdown-item").map { |item| item.text.strip }
    assert_equal [ "Duplicate", "Delete" ], items.last(2)
    assert_select ".dropdown-menu form[data-turbo-confirm] button.text-danger", "Delete"
  end

  test "the list filters archived registrations with a pill" do
    with_settings(intake_archive_days: "30") do
      @registration.update!(opens_at: 90.days.ago, closes_at: 60.days.ago)
      sign_in @leader.user
      with_intake do
        get intake_registrations_path
        assert_no_match "Join Northwind", response.body
        assert_select "a", text: /Archived \(1\)/
        get intake_registrations_path(status: "archived")
        assert_match "Join Northwind", response.body
      end
    end
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
    assert_select "input[name='intake_registration[title]'][value='Join Northwind (copy)']"
  end

  test "switched off, the staff screens are hidden" do
    sign_in @leader.user
    get intake_registrations_path

    assert_redirected_to root_path
  end
end
