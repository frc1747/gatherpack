require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# The Forms panel on an event page: one row per form with one button, and
# the New link and empty line only for people who can add a form.
class FormEventPanelTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @event = Event.create!(name: "Saturday Build", event_type: event_types(:one), team: @den_a, start_time: 3.days.from_now.change(hour: 9))
    @poll = create_world_form("Coming Saturday?", team: @den_a, include: [ @den_a ], respond: "self_and_leaders", read: "family", event: @event,
      closes_at: 2.days.from_now.change(hour: 12))
    @poll.form_questions.create!(kind: :intent, label: "Are you coming?", required: true)
    @slip = create_world_form("Trip Slip", team: @den_a, include: [ @den_a ], respond: "self_and_leaders", read: "family", event: @event)
  end

  test "a leader sees one row per form with its state in words, one Responses button, and the New link" do
    with_feature do
      as(:den_a_leader) do
        get event_path(@event)
        assert_response :success
        assert_select "#event-forms .card-header", text: "Forms"
        assert_select "#event-forms .list-group-flush > .list-group-item", count: 2
        assert_select "#event-forms .list-group-item", text: /Coming Saturday\?\s+Taking answers until #{Regexp.escape(@poll.closes_at.strftime("%B %-d, %Y"))}/
        assert_select "#event-forms .list-group-item", text: /Trip Slip\s+Taking answers/
        css_select("#event-forms .list-group-item").each do |row|
          assert_equal 1, row.css(".btn").size
          assert_equal [ "Responses" ], row.css("a.btn.btn-sm.btn-outline-secondary").map(&:text)
        end
        assert_select "#event-forms .badge", count: 0
        assert_select "#event-forms a", text: /Results|Tally|Printable list/, count: 0
        assert_select "#event-forms .card-footer a.btn.btn-sm.btn-outline-secondary[href=?]", new_form_path(event_id: @event.id), text: "New form for this event"
        assert_select "#event-forms", text: /No forms for this event/, count: 0
      end
    end
  end

  test "a member sees their own forms, each with one button for their job, and no New link" do
    with_feature do
      as(:a2) do
        get event_path(@event)
        assert_select "#event-forms .list-group-item", count: 2
        css_select("#event-forms .list-group-item").each do |row|
          assert_equal [ "Fill in" ], row.css("a.btn.btn-sm.btn-primary").map(&:text)
          assert_equal 1, row.css(".btn").size
        end
        assert_select "#event-forms a.btn[href=?]", edit_form_response_path(@poll, person(:a2))
        assert_select "#event-forms a", text: /New form/, count: 0
        assert_select "#event-forms .card-footer", count: 0
      end
    end
  end

  test "an event with no forms shows the empty line and New link to leaders and no panel to members" do
    bare = Event.create!(name: "Den A Trip", event_type: event_types(:one), team: @den_a, start_time: 1.week.from_now)
    with_feature do
      as(:den_a_leader) do
        get event_path(bare)
        assert_select "#event-forms .list-group-item", count: 0
        assert_select "#event-forms p.text-muted", text: "No forms for this event."
        assert_select "#event-forms .card-footer a[href=?]", new_form_path(event_id: bare.id), text: "New form for this event"
      end
      as(:a2) do
        get event_path(bare)
        assert_response :success
        assert_select "#event-forms", count: 0
      end
    end
  end

  private

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
