require "test_helper"
require_relative "../support/commitments_world"
require_relative "../support/push_connector_test_support"

class CommitmentsPushConnectorTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include CommitmentsWorld
  include PushConnectorTestSupport

  setup do
    travel_to Time.zone.parse("2026-10-20 12:00")
    host! "localhost"
    build_commitments_world
    @commitment = create_world_commitment
    apply_push_settings(commitments: true)
    create_push_gateway
    # Member, member2 and kid owe; member2 is done.
    @commitment.commitment_adjustments.create!(person: person(:member2), credits: 2, reason: "Done early")
    sign_in person(:admin).user
    clear_enqueued_jobs
  end

  teardown { restore_push_settings }

  def send_message(subject: "Shifts", body: "Please sign up.")
    post message_commitment_path(@commitment), params: { subject: subject, body: body }
  end

  test "pushes to opted-in people who were emailed, not to those who met it" do
    [ :member, :member2, :outsider ].each { |name| subscribe(person(name), :commitments) }

    assert_enqueued_jobs(2, only: SendEmailJob) { send_message }

    assert_redirected_to commitment_path(@commitment)
    assert_equal [ person(:member).user.id ], pushed_user_ids
    assert_equal [ "Reminder: Shifts" ], push_titles
    assert_equal [ "/commitments/#{@commitment.to_param}" ], push_paths
  end

  test "the title names no one" do
    subscribe(person(:kid), :commitments)

    send_message

    assert_no_match(/Kid|Member/, push_titles.join)
  end

  test "people who haven't opted in get no push" do
    assert_enqueued_jobs(2, only: SendEmailJob) { send_message }

    assert_empty enqueued_pushes
  end

  test "nothing is pushed with the flag off, and the emails still go" do
    subscribe(person(:member), :commitments)
    apply_push_settings(push: false, commitments: true)

    assert_enqueued_jobs(2, only: SendEmailJob) { send_message }

    assert_empty enqueued_pushes
  end

  test "nothing is pushed when the message isn't sent" do
    subscribe(person(:member), :commitments)

    send_message(body: " ")

    assert_empty enqueued_pushes
    assert_empty enqueued_jobs.select { |job| job[:job] == SendEmailJob }
  end

  test "someone who can't send gets no push sent" do
    subscribe(person(:kid), :commitments)
    sign_in person(:member).user

    send_message

    assert_empty enqueued_pushes
  end

  test "the emails go and the page redirects when push fails" do
    subscribe(person(:member), :commitments)

    replacing(GatherPack::PushChannel, :deliver, ->(*, **) { raise "push is down" }) do
      assert_enqueued_jobs(2, only: SendEmailJob) { send_message }
    end
    assert_redirected_to commitment_path(@commitment)
  end
end
