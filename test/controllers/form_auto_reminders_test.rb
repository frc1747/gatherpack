require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# The automatic reminder setting on a form's edit page, the line on its page,
# and how the reminder history shows an automatic send.
class FormAutoRemindersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @form = create_world_form(closes_at: 5.days.from_now, auto_reminder_days: 3)
  end

  test "the edit page asks how many days before the deadline" do
    with_feature do
      as(:admin) do
        get edit_form_path(@form, tab: "responses")
        assert_select "input[name='form[auto_reminder_days]'][value='3']"
        assert_match(/Remind people who haven't answered/, response.body)
      end
    end
  end

  test "it's hidden with no deadline or with the flag off" do
    with_feature do
      as(:admin) do
        @form.update!(closes_at: nil)
        get edit_form_path(@form, tab: "responses")
        assert_select "input[name='form[auto_reminder_days]']", false
      end
    end
    with_settings(feature_forms: "true") do
      as(:admin) do
        @form.update!(closes_at: 5.days.from_now)
        get edit_form_path(@form, tab: "responses")
        assert_select "input[name='form[auto_reminder_days]']", false
        get form_path(@form)
        assert_no_match(/automatic reminder/, response.body)
      end
    end
  end

  test "a leader sets the days" do
    with_feature do
      as(:admin) do
        patch form_path(@form), params: { form: { auto_reminder_days: "2" } }
        assert_equal 2, @form.reload.auto_reminder_days
      end
    end
  end

  test "the form page says who and when" do
    with_feature do
      as(:admin) do
        get form_path(@form)
        date = (5.days.from_now - 3.days).in_time_zone(Settings[:time_zone].presence || "UTC").strftime("%B %-d")
        assert_match(/An automatic reminder goes out #{date} to people who haven't answered\./, response.body)

        @form.update!(auto_reminder_days: 0)
        get form_path(@form)
        assert_no_match(/automatic reminder/, response.body)
      end
    end
  end

  test "a draft says a reminder is set" do
    @form.update!(status: :draft)
    with_feature do
      as(:admin) do
        get form_path(@form)
        assert_match(/An automatic reminder goes out .* to people who haven't answered/, response.body)
      end
    end
  end

  test "the history shows an automatic reminder" do
    @form.form_reminders.create!(sent_at: Time.current, recipient_count: 4, filter: { automatic: true })
    with_feature do
      as(:admin) do
        get form_path(@form)
        assert_match(/Last reminder: .* to 4 people \(Automatic\)\./, response.body)
      end
    end
  end

  private

  def with_feature(&block)
    with_settings(feature_forms: "true", feature_forms_auto_reminders: "true", &block)
  end

  def as(name)
    sign_in person(name).user
    yield
  ensure
    sign_out :user
  end
end
