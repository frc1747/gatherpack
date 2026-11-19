require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/push_connector_test_support"

class FormReminderPushConnectorTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include FormsWorld
  include PushConnectorTestSupport

  setup do
    build_person_fields_world
    apply_push_settings(forms: true)
    create_push_gateway
    @form = create_world_form
    @sender = FormReminderSender.new(@form, [ person(:a1), person(:a2) ], include_guardians: true)
    clear_enqueued_jobs
  end

  teardown { restore_push_settings }

  def remind
    @sender.send!(sent_by: person(:pack_leader))
  end

  test "sends one push to each person who was emailed and is opted in" do
    # A1 and both parents are emailed; B1 is not a subject, and A2 is opted out.
    [ :a1, :parent_a1, :parent_a2, :b1 ].each { |name| subscribe(person(name), :forms) }

    assert_enqueued_jobs(4, only: SendEmailJob) { remind }

    assert_equal [ person(:a1), person(:parent_a1), person(:parent_a2) ].map { |p| p.user.id }.sort, pushed_user_ids
  end

  test "opens the response, and names only the form" do
    subscribe(person(:parent_a1), :forms)

    remind

    assert_equal [ "Reminder: Meal Choices" ], push_titles
    assert_equal [ "/forms/#{@form.to_param}/responses/#{person(:a1).id}/edit" ], push_paths
    assert_no_match(/A1/, push_titles.join)
  end

  test "people who haven't opted in get no push, and still get the email" do
    assert_enqueued_jobs(4, only: SendEmailJob) { remind }

    assert_empty enqueued_pushes
  end

  test "nothing is pushed with the flag off, and the emails still go" do
    subscribe(person(:a1), :forms)
    apply_push_settings(push: false, forms: true)

    assert_enqueued_jobs(4, only: SendEmailJob) { remind }

    assert_empty enqueued_pushes
  end

  test "nothing is pushed for the forms topic while forms are off" do
    subscribe(person(:a1), :forms)
    apply_push_settings(forms: false)

    remind

    assert_empty enqueued_pushes
  end

  test "the emails go and the reminder is recorded when push fails" do
    subscribe(person(:a1), :forms)

    replacing(GatherPack::PushChannel, :deliver, ->(*, **) { raise "push is down" }) do
      assert_enqueued_jobs(4, only: SendEmailJob) do
        assert_nothing_raised { remind }
      end
    end
    assert_equal 1, @form.form_reminders.count
  end

  test "an error from the emails still raises" do
    replacing(SendEmailJob, :perform_later, ->(*) { raise "queue is down" }) do
      assert_raises(RuntimeError) { remind }
    end
  end
end
