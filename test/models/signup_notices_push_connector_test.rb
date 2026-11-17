require "test_helper"
require_relative "../support/signups_world"
require_relative "../support/push_connector_test_support"

class SignupNoticesPushConnectorTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SignupsWorld
  include PushConnectorTestSupport

  setup do
    travel_to Time.zone.parse("2026-10-11 12:00")
    build_signups_world
    apply_push_settings(isolated: false)
    create_push_gateway
    @sheet = create_world_sheet
    @cashier = @sheet.signup_positions.create!(name: "Cashier", capacity: 4)
    @cook = @sheet.signup_positions.create!(name: "Cook", capacity: 4)
    # An admin signs the student up on behalf of the sibling, so
    # three people are emailed about it.
    @signup = Signup.place!(slot: slot_for(@cashier), person: person(:student), signed_up_by: person(:admin), on_behalf_of: person(:sibling))
    clear_enqueued_jobs
  end

  teardown { restore_push_settings }

  def opt_in(*names)
    names.each { |name| subscribe(person(name), :shifts) }
  end

  def notices
    SignupNotices.new
  end

  test "a reminder goes to the phones of the people it emails who opted in" do
    opt_in :student, :admin, :outsider

    assert_enqueued_jobs(3, only: SendEmailJob) { notices.reminder(@signup) }

    assert_equal [ person(:student), person(:admin) ].map { |p| p.user.id }.sort, pushed_user_ids
    assert_equal [ "Reminder: Cashier, Game Day" ] * 2, push_titles
    assert_equal [ "/signup_sheets/#{@sheet.to_param}" ] * 2, push_paths
  end

  test "the title names no one" do
    opt_in :admin

    notices.reminder(@signup)

    assert_no_match(/Student|Sibling|Admin/, push_titles.join)
  end

  test "event changes, cancellations and moves are pushed to the people emailed" do
    opt_in :student

    notices.event_changed(@event, start_time_was: @event.start_time - 1.hour, end_time_was: @event.end_time - 1.hour)
    notices.cancelled(@signup, by: person(:admin))
    notices.moved(@signup, from: slot_for(@cook), by: person(:admin))

    assert_equal [ "Time changed: Game Day", "Sign-up cancelled: Cashier, Game Day", "Sign-up moved: Cashier, Game Day" ], push_titles
    assert_equal [ "/signup_sheets/#{@sheet.to_param}" ] * 3, push_paths
  end

  test "a time change goes only to people with a sign-up at the event" do
    opt_in :student, :worker

    notices.event_changed(@event, start_time_was: @event.start_time - 1.hour, end_time_was: @event.end_time - 1.hour)

    assert_equal [ person(:student).user.id ], pushed_user_ids
  end

  test "confirmations and organizers' messages send no push" do
    opt_in :student, :admin, :sibling

    assert_enqueued_jobs(3, only: SendEmailJob) do
      Signup.place!(slot: slot_for(@cook), person: person(:student), signed_up_by: person(:admin), on_behalf_of: person(:sibling))
    end
    assert_enqueued_jobs(3, only: SendEmailJob) do
      notices.message(@sheet, @event, subject: "Bring ID", body: "See you there", from: person(:admin))
    end

    assert_empty enqueued_pushes
  end

  test "people who haven't opted in get no push" do
    notices.reminder(@signup)

    assert_empty enqueued_pushes
  end

  test "nothing is pushed with the flag off, and the emails still go" do
    opt_in :student
    apply_push_settings(push: false, signups: true, isolated: false)

    assert_enqueued_jobs(3, only: SendEmailJob) { notices.reminder(@signup) }

    assert_empty enqueued_pushes
  end

  test "nothing is pushed while sign-up sheets are off" do
    opt_in :student
    apply_push_settings(signups: false, isolated: false)

    notices.reminder(@signup)

    assert_empty enqueued_pushes
  end

  test "the emails go and nothing raises when push fails" do
    opt_in :student

    replacing(GatherPack::PushChannel, :deliver, ->(*, **) { raise "push is down" }) do
      assert_enqueued_jobs(3, only: SendEmailJob) do
        assert_nothing_raised { notices.reminder(@signup) }
      end
    end
  end

  test "an error from the emails still raises" do
    replacing(SendEmailJob, :perform_later, ->(*) { raise "queue is down" }) do
      assert_raises(RuntimeError) { notices.reminder(@signup) }
    end
  end
end
