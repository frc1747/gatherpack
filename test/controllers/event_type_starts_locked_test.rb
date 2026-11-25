require "test_helper"
require "pstore"
require "tmpdir"

class EventTypeStartsLockedControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"
    @saved_store = Settings.instance.store
    @saved_flag = Settings.get(:feature_event_type_starts_locked).instance_variable_get(:@value)
    @settings_dir = Dir.mktmpdir
    Settings.instance.store = PStore.new(File.join(@settings_dir, "settings.pstore"), true)

    admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: admin, first_name: "Admin", last_name: "Test")
    sign_in admin
    @event_type = EventType.create!(name: "Outreach")
  end

  teardown do
    Settings.get(:feature_event_type_starts_locked).instance_variable_set(:@value, @saved_flag)
    Settings.instance.store = @saved_store
    FileUtils.remove_entry(@settings_dir)
  end

  test "an admin marks an event type so its new events start locked" do
    Settings[:feature_event_type_starts_locked] = "true"

    get edit_event_type_path(@event_type)
    assert_select "input[name='event_type[starts_locked]']"

    patch event_type_path(@event_type), params: { event_type: { name: "Outreach", starts_locked: "1" } }

    assert @event_type.reload.starts_locked?
  end

  test "with the feature off, the form has no tick box and ignores the field" do
    get edit_event_type_path(@event_type)
    assert_select "input[name='event_type[starts_locked]']", count: 0

    patch event_type_path(@event_type), params: { event_type: { name: "Outreach", starts_locked: "1" } }

    assert_not @event_type.reload.starts_locked?
  end
end
