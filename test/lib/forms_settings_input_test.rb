require "test_helper"

# Forms asks for a team picker for its extra audience setting only where the
# settings pickers exist, and the setting keeps its one-name-per-line text
# either way.
class FormsSettingsInputTest < ActiveSupport::TestCase
  INITIALIZER = Rails.root.join("config/initializers/forms.rb")

  test "the team picker registration is guarded by Settings.input being there" do
    assert_includes File.read(INITIALIZER), "Settings.input(:forms_creator_extra_audience_teams, :teams) if Settings.respond_to?(:input)"
  end

  test "the setting is drawn with the team picker where pickers exist, and stays text" do
    setting = Settings.get(:forms_creator_extra_audience_teams)
    assert_equal :text, setting.setting_type

    if Settings.respond_to?(:input)
      assert_equal :teams, Settings.input_for(:forms_creator_extra_audience_teams).kind
    else
      assert_not Settings.respond_to?(:input_for), "without pickers the settings page draws its text box as before"
    end
  end
end
