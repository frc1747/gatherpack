require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# The Remind screen: who it emails, the guardian choice, and the messages a
# form keeps for its next reminder. The world's Pack form is open to family,
# so 7 people owe a response (A1, A2, B1, three leaders, the assistant) and
# A1's and A2's parents are guardians who can nudge.
class FormRemindersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @form = create_world_form
    @sandwich = add_choice(@form, "Sandwich", [ "Slim 1", "Slim 4", "Big John" ], required: true)
  end

  test "the first reminder starts with guardians left out, and later ones include them" do
    with_feature do
      as(:pack_leader) do
        get reminder_form_path(@form)
        assert_response :success
        assert_select "input[type=checkbox][name=include_guardians]:not([checked])"
        assert_select "[data-form-reminder-when=off]:not([hidden])", text: /Email 7 people\./
        assert_select "[data-form-reminder-when=on][hidden]", text: /Email 9 people: 7 about their own response and 2 guardians\./

        assert_enqueued_jobs 7, only: SendEmailJob do
          post remind_form_path(@form), params: { include_guardians: "0" }
        end
        assert_equal [ "a1@example.com", "a2@example.com" ], sent_to & [ "a1@example.com", "a2@example.com", "parenta1@example.com" ]
        reminder = @form.form_reminders.last
        assert_equal [ 7, 0, false ], [ reminder.recipient_count, reminder.guardian_count, reminder.guardians_included ]

        get form_path(@form)
        assert_select ".form-text", text: /to 7 people, guardians not emailed/

        get reminder_form_path(@form)
        assert_select "input[type=checkbox][name=include_guardians][checked]"
        clear_enqueued_jobs
        assert_enqueued_jobs 9, only: SendEmailJob do
          post remind_form_path(@form), params: { include_guardians: "1" }
        end
        assert_equal [ 9, 2, true ], @form.form_reminders.order(:sent_at).last.then { [ _1.recipient_count, _1.guardian_count, _1.guardians_included ] }
        get form_path(@form)
        assert_select ".form-text", text: /to 9 people \(2 guardians\)/
      end
    end
  end

  test "guardians who have to sign are emailed even when guardians are left out" do
    add_signature(@form, "Parent", signer: "guardian")
    respond(@form, :a1, as: :a1, answers: { "sandwich" => "Slim 4" })
    with_feature do
      as(:pack_leader) do
        get reminder_form_path(@form)
        assert_select "[data-form-reminder-when=off]", text: /1 guardian is emailed either way/

        post remind_form_path(@form), params: { include_guardians: "0" }
      end
    end
    assert_includes sent_to, "parenta1@example.com"
    assert_not_includes sent_to, "parenta2@example.com"
    assert_equal 1, @form.form_reminders.last.guardian_count
  end

  test "messages are used, saved for next time, and go back to the default" do
    with_feature do
      as(:pack_leader) do
        post remind_form_path(@form), params: { include_guardians: "1",
          message: "Students fill this in **themselves**.\r\n",
          guardian_message: "{form} isn't finished yet{due}. Please remind them:" }
      end
      assert_equal "Students fill this in **themselves**.", @form.reload.reminder_message
      assert_equal "{form} isn't finished yet{due}. Please remind them:", @form.guardian_reminder_message
      assert_includes body_to("a2@example.com"), "<p>Students fill this in <strong>themselves</strong>.</p>"
      assert_includes body_to("parenta2@example.com"), "<p>Meal Choices isn't finished yet. Please remind them:</p>"

      as(:pack_leader) do
        get reminder_form_path(@form)
        assert_select "textarea[name=message]", text: "Students fill this in **themselves**."

        post remind_form_path(@form), params: { include_guardians: "1", message: FormReminderSender::DEFAULT_MESSAGE, guardian_message: "" }
      end
      assert_nil @form.reload.reminder_message
      assert_nil @form.guardian_reminder_message
    end

    copy = @form.reload.tap { _1.update!(reminder_message: "Kept") }.duplicate!(title: "Copy")
    assert_equal "Kept", copy.reminder_message
  end

  test "with no saved message the email is the one sent before messages could be changed" do
    @form.update!(closes_at: Time.zone.parse("2026-10-20 12:00"))
    sender = FormReminderSender.new(@form, [ person(:a2) ])
    url = Rails.application.routes.url_helpers.edit_form_response_url(@form, person(:a2).id)
    assert_equal "<p>Hi A2,</p><p>Please complete <strong>Meal Choices</strong> by October 20 for:</p><ul><li><a href=\"#{url}\">You</a></li></ul>",
      sender.body(person(:a2))
    assert_equal "<p>Hi ParentA2,</p><p>Please complete <strong>Meal Choices</strong> by October 20 for:</p><ul><li><a href=\"#{url}\">A2 World</a></li></ul>",
      sender.body(person(:parent_a2))
  end

  test "filled-in values are shown as written, not as Markdown or HTML" do
    @form.update!(title: "<b>Trip</b> *2026*")
    body = FormReminderSender.new(@form, [ person(:a2) ]).body(person(:a2))
    assert_includes body, "<strong>&lt;b&gt;Trip&lt;/b&gt; *2026*</strong>"
  end

  test "a title with stray spaces or quotes still reads as before, and names are escaped" do
    @form.update!(title: " Pat's Trip ")
    person(:a2).update!(first_name: "<i>Al</i>_x")
    sender = FormReminderSender.new(@form, [ person(:a2) ], message: "Hi again {first name}, see **{form}**:")
    body = sender.body(person(:a2))
    assert_includes body, "<p>Hi &lt;i&gt;Al&lt;/i&gt;_x,</p>"
    assert_includes body, "<p>Hi again &lt;i&gt;Al&lt;/i&gt;_x, see <strong>Pat's Trip</strong>:</p>"
  end

  test "one email per guardian lists all of their people" do
    relate_world(:parent_a1, :a2, @parent_of)
    with_feature do
      as(:pack_leader) do
        get reminder_form_path(@form)
        assert_select "[data-form-reminder-when=on]", text: /Email 9 people: 7 about their own response and 2 guardians\./
        post remind_form_path(@form), params: { include_guardians: "1" }
      end
    end
    assert_equal 1, sent_to.count("parenta1@example.com")
    assert_match(/A1 World.*A2 World/, body_to("parenta1@example.com"))
  end

  test "a send that reaches no guardians says nothing about them, even on a form that allows them" do
    with_feature do
      as(:pack_leader) do
        get reminder_form_path(@form, team_id: @den_b.id)
        assert_select "input[name=include_guardians]", count: 0
        assert_select "textarea[name=guardian_message]", count: 0
        assert_select "body", text: /guardian/i, count: 0
      end
    end
  end

  test "a large send gets a stronger warning" do
    18.times { |i| create_world_person("Extra#{i}", @pack) }
    with_feature do
      as(:pack_leader) do
        get reminder_form_path(@form)
        assert_select "[data-form-reminder-when=on] .alert-warning", text: "This will email 27 people."
        assert_select "[data-form-reminder-when=off] .alert-warning", text: "This will email 25 people."
      end
    end
  end

  test "a form only the subject answers says nothing about guardians" do
    @form.update!(respond_permission: "self_and_leaders")
    with_feature do
      as(:pack_leader) do
        get reminder_form_path(@form)
        assert_select "input[name=include_guardians]", count: 0
        assert_select "textarea[name=guardian_message]", count: 0
        assert_select "body", text: /guardian/i, count: 0
        assert_select "p", text: /Email 7 people\./
      end
    end
  end

  test "a form only guardians answer emails them with no choice to leave them out" do
    @form.update!(respond_permission: "guardians")
    with_feature do
      as(:pack_leader) do
        get reminder_form_path(@form)
        assert_select "input[name=include_guardians]", count: 0
        assert_select "textarea[name=guardian_message]"
        assert_select "textarea[name=message]", count: 0
        assert_enqueued_jobs 2, only: SendEmailJob do
          post remind_form_path(@form), params: { include_guardians: "0" }
        end
      end
    end
    assert_nil @form.form_reminders.last.guardians_included
  end

  test "people nobody can email about are named" do
    person(:b1).update!(user: nil)
    with_feature do
      as(:pack_leader) do
        get reminder_form_path(@form)
        assert_select "[data-form-reminder-when=off]", text: /1 person won't be reminded.*B1 World/m
      end
    end
  end

  test "Update preview shows the typed message without sending" do
    with_feature do
      as(:pack_leader) do
        assert_no_enqueued_jobs only: SendEmailJob do
          post remind_form_path(@form), params: { preview: "1", include_guardians: "1", message: "Hello there" }
        end
        assert_response :unprocessable_content
        assert_select ".border p", text: "Hello there"
        assert_nil @form.reload.reminder_message
      end
    end
  end

  test "the team filter carries through, and only form managers can remind" do
    with_feature do
      as(:den_a_leader) do
        get reminder_form_path(@form)
        assert_redirected_to root_path
      end
      as(:pack_leader) do
        get form_path(@form, team_id: @den_a.id)
        assert_select "a[href=?]", reminder_form_path(@form, team_id: @den_a.id)
        get reminder_form_path(@form, team_id: @den_a.id)
        assert_select "input[type=hidden][name=team_id][value=?]", @den_a.id
        post remind_form_path(@form), params: { team_id: @den_a.id, include_guardians: "0" }
      end
    end
    assert_equal({ "team_id" => @den_a.id }, @form.form_reminders.last.filter)
  end

  private

  def sent_emails
    enqueued_jobs.select { |job| job["job_class"] == "SendEmailJob" }.map { |job| job["arguments"] }
  end

  def sent_to
    sent_emails.map(&:second)
  end

  def body_to(email)
    sent_emails.detect { |arguments| arguments.second == email }&.fourth
  end

  def with_feature(&block)
    with_settings(feature_forms: "true", &block)
  end

  def as(name)
    sign_in person(name).user
    yield
  ensure
    sign_out :user
  end
end
