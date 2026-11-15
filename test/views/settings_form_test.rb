require "test_helper"

# settings/_form: some settings on a feature's own page.
class SettingsFormTest < ActionView::TestCase
  helper SettingsInputsHelper

  setup do
    @path = Rails.root.join("tmp", "settings-form-test-#{Process.pid}.pstore").to_s
    File.delete(@path) if File.exist?(@path)
    @original_store = Settings.instance.store
    Settings.instance.store = PStore.new(@path, true)
    @original_inputs = Settings.instance.inputs.dup
    @original_settings = Settings.instance.settings.dup

    Settings.register(:input_test_teams, :text, "Who Can Ask", "", "Input Tests", "Teams who can ask")
    Settings.register(:input_test_flag, :boolean, "Ask First", "false", "Input Tests", "A switch")
    Settings.register(:input_test_plain, :string, "Plain", "", "Input Tests", "Typed")
    Settings.register(:input_test_token, :secret, "Token", "", "Input Tests", "A secret")
    Settings.input(:input_test_teams, :teams)
    Settings.set(:input_test_teams, "Alpha Team")
    Settings.set(:input_test_plain, "typed")
    Settings.set(:input_test_token, "hidden-value")
  end

  teardown do
    Settings.instance.store = @original_store
    Settings.instance.inputs.replace(@original_inputs)
    Settings.instance.settings.replace(@original_settings)
    File.delete(@path) if File.exist?(@path)
  end

  def render_form(admin:)
    view.define_singleton_method(:admin?) { admin }
    render partial: "settings/form", locals: { keys: %i[input_test_teams input_test_flag input_test_plain input_test_token missing_key], return_to: "/teams" }
  end

  test "draws the given settings with their pickers and a return path" do
    render_form(admin: true)

    assert_select "form[action='#{update_settings_path}'][method=post]"
    assert_select "input[type=hidden][name=return_to][value='/teams']"
    assert_select "fieldset[disabled]", count: 0
    assert_select "input[type=checkbox][name='settings[input_test_teams][values][]'][value='Alpha Team'][checked]"
    assert_select "select[name='settings[input_test_flag]']"
    assert_select "input[name='settings[input_test_plain]'][value='typed']"
    assert_select "input[name='settings[title]']", count: 0
    assert_select "input[type=submit][value=Save]"
  end

  test "a type it doesn't know is a blank password field that keeps its value" do
    render_form(admin: true)

    assert_select "input[type=password][name='settings[input_test_token]']:not([value])"
    assert_select "input[type=hidden][name='keep_if_blank[]'][value='input_test_token']"
    assert_no_match "hidden-value", rendered
  end

  test "someone who isn't an admin sees the values read-only, with no Save" do
    render_form(admin: false)

    assert_select "fieldset[disabled] input[type=checkbox][value='Alpha Team'][checked]"
    assert_select "fieldset[disabled] input[name='settings[input_test_plain]'][value='typed']"
    assert_select "input[type=submit]", count: 0
    assert_select "input[name=return_to]", count: 0
    assert_match "Only admins can change these settings.", rendered
  end
end
