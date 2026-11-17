require "test_helper"

class SettingsInputsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "localhost"

    @path = Rails.root.join("tmp", "settings-controller-test-#{Process.pid}.pstore").to_s
    File.delete(@path) if File.exist?(@path)
    @original_store = Settings.instance.store
    Settings.instance.store = PStore.new(@path, true)
    @original_inputs = Settings.instance.inputs.dup
    @original_pages = Settings.instance.pages.dup
    @original_settings = Settings.instance.settings.dup

    Settings.register(:input_test_teams, :text, "Who Can Ask", "", "Input Tests", "Teams who can ask")
    Settings.register(:input_test_grants, :text, "Organizers", "", "Input Tests", "Badges that organize")
    Settings.register(:input_test_kinds, :string, "What Members Record", "used, moved", "Input Tests", "Kinds")
    Settings.register(:input_test_notice, :string, "Notices", "daily", "Input Tests", "When")
    Settings.register(:input_test_domains, :string, "Domains", "a.com, b.com", "Input Tests", "Domains")
    Settings.register(:input_test_start, :string, "Season Start", "05-01", "Input Tests", "MM-DD")
    Settings.register(:input_test_archive, :string, "Archive Before", "", "Input Tests", "A date or days")
    Settings.register(:input_test_plain, :string, "Plain", "", "Input Tests", "Typed")
    Settings.register(:input_test_on, :string, "Starts On", "", "Input Tests", "A date")
    Settings.register(:input_test_unit, :string, "Unit", "each", "Input Tests", "Any word")
    Settings.register(:input_test_steps, :text, "Steps", "[]", "Input Tests", "Names as JSON")
    Settings.register(:input_test_token, :string, "Token", "", "Input Tests", "Not shown on its page")

    Settings.input(:input_test_teams, :teams)
    Settings.input(:input_test_grants, :badge_grants)
    Settings.input(:input_test_kinds, :checkboxes, choices: [ [ "Used", "used" ], [ "Moved", "moved" ], [ "Counted", "counted" ] ])
    Settings.input(:input_test_notice, :select, choices: [ [ "Off", "off" ], [ "Each time", "each" ], [ "Daily", "daily" ] ])
    Settings.input(:input_test_domains, :list)
    Settings.input(:input_test_start, :month_day)
    Settings.input(:input_test_archive, :date_or_days)
    Settings.input(:input_test_on, :date)
    Settings.input(:input_test_unit, :text, suggestions: %w[each box])
    Settings.input(:input_test_steps, :partial, partial: "settings_inputs_test/steps",
      to_text: ->(posted, _current) { JSON.generate(Array(posted[:names]).compact_blank) })

    @original_view_paths = SettingsController.view_paths
    SettingsController.prepend_view_path(Rails.root.join("test/fixtures/views"))

    Badge.create!(name: "Trip Lead", color: "blue", short: "TL", badge_type: badge_types(:one))

    @admin_user = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: @admin_user, first_name: "Ada", last_name: "Admin")
    @member_user = User.create!(email: "member@example.com", password: "Password1!")
    Person.create!(user: @member_user, first_name: "Jo", last_name: "Member")
  end

  teardown do
    SettingsController.view_paths = @original_view_paths
    Settings.instance.store = @original_store
    Settings.instance.inputs.replace(@original_inputs)
    Settings.instance.pages.replace(@original_pages)
    Settings.instance.settings.replace(@original_settings)
    File.delete(@path) if File.exist?(@path)
  end

  # --- the page --------------------------------------------------------------

  test "each picker shows the saved value" do
    Settings.set(:input_test_teams, "Beta Team\nGone Team")
    Settings.set(:input_test_grants, "Trip Lead > Alpha Team\nOld Badge")
    Settings.set(:input_test_kinds, "counted")
    Settings.set(:input_test_notice, "each")
    Settings.set(:input_test_domains, "x.com, y.com")
    Settings.set(:input_test_start, "09-15")
    Settings.set(:input_test_archive, "30")
    Settings.set(:input_test_on, "2026-03-01")
    Settings.set(:input_test_unit, "box")
    Settings.set(:input_test_steps, '["First","Second"]')
    sign_in @admin_user

    get settings_path

    assert_response :success
    assert_select "input[type=checkbox][name='settings[input_test_teams][values][]'][value='Beta Team'][checked]"
    assert_select "input[type=checkbox][name='settings[input_test_teams][values][]'][value='Alpha Team']:not([checked])"
    assert_select "label", text: "Not found: Gone Team"
    assert_select "select[name='settings[input_test_grants][rows][0][badge]'] option[selected]", text: "Trip Lead"
    assert_select "select[name='settings[input_test_grants][rows][0][team]'] option[selected]", text: "Alpha Team"
    assert_select "input[type=hidden][name='settings[input_test_grants][rows][1][line]'][value='Old Badge']"
    assert_select "div", text: "Not found: Old Badge"
    assert_select "select[name='settings[input_test_grants][rows][2][badge]'] option[selected]", count: 0
    assert_select "select[name='settings[input_test_grants][rows][2][team]'] option[value='']", text: "Up to: their own teams"
    assert_select "input[type=checkbox][name='settings[input_test_kinds][values][]'][value='counted'][checked]"
    assert_select "select[name='settings[input_test_notice]'] option[selected][value='each']"
    assert_select "input[name='settings[input_test_domains][items][]'][value='y.com']"
    assert_select "select[name='settings[input_test_start][month]'] option[selected][value='9']"
    assert_select "select[name='settings[input_test_start][day]'] option[selected][value='15']"
    assert_select "input[type=radio][name='settings[input_test_archive][mode]'][value='days'][checked]"
    assert_select "input[name='settings[input_test_archive][days]'][value='30']"
    assert_select "input[type=date][name='settings[input_test_on]'][value='2026-03-01']"
    assert_select "input[type=text][name='settings[input_test_unit]'][value='box'][list]"
    assert_select "datalist option[value='each']"
    assert_select "input[name='settings[input_test_steps][names][]'][value='Second']"
    assert_select ".test-builder", text: "settings"
    assert_match "Default: See the field", response.body
  end

  test "a setting without an input is still a text box" do
    Settings.set(:input_test_plain, "typed")
    sign_in @admin_user

    get settings_path

    assert_select "input[type=text][name='settings[input_test_plain]'][value='typed']"
    assert_select "input[name='settings[title]']"
  end

  test "the default reads as words" do
    sign_in @admin_user

    get settings_path

    assert_match "Default: Used, Moved", response.body
    assert_match "Default: May 1", response.body
    assert_match "Default: Never", response.body
  end

  test "a value the picker can't read is shown as saved" do
    Settings.set(:input_test_start, "spring")
    sign_in @admin_user

    get settings_path

    assert_select "input[type=text][name='settings[input_test_start]'][value='spring']"
  end

  test "a group with its own page is one line with a link" do
    Settings.page("Input Tests", :root_path, label: "Input test settings")
    sign_in @admin_user

    get settings_path

    assert_select "a[href='/']", text: "Input test settings"
    assert_select "input[name='settings[input_test_plain]']", count: 0
    assert_select "input[name='settings[title]']"
  end

  test "a group whose page is off is drawn on the settings page" do
    Settings.page("Input Tests", :root_path, label: "Input test settings", if: -> { false })
    sign_in @admin_user

    get settings_path

    assert_select "a", text: "Input test settings", count: 0
    assert_select "input[name='settings[input_test_plain]']"
  end

  test "only admins see the page" do
    sign_in @member_user

    get settings_path

    assert_redirected_to root_path
  end

  # --- saving ----------------------------------------------------------------

  # Posted as the form posts them, so this is also the page with JavaScript off.
  def page_params
    {
      input_test_teams: { values: [ "", "Beta Team", "Gone Team" ] },
      input_test_grants: {
        rows: {
          "0" => { line: "Trip Lead > Alpha Team", badge: "Trip Lead", team: "Alpha Team" },
          "1" => { line: "Old Badge" },
          "2" => { line: "", badge: "", team: "" }
        }
      },
      input_test_kinds: { values: [ "", "counted" ] },
      input_test_notice: "each",
      input_test_domains: { items: [ "", "x.com", "y.com", "" ] },
      input_test_start: { month: "9", day: "15" },
      input_test_archive: { mode: "days", date: "", days: "30" },
      input_test_plain: "typed",
      input_test_on: "2026-03-01",
      input_test_unit: "box",
      input_test_steps: { names: [ "First", "Second", "" ] }
    }
  end

  test "saving the page unchanged keeps every value's text" do
    saved = {
      input_test_teams: "Beta Team\r\nGone Team",
      input_test_grants: "Trip Lead > Alpha Team\r\nOld Badge",
      input_test_kinds: "counted",
      input_test_notice: "each",
      input_test_domains: "x.com, y.com",
      input_test_start: "09-15",
      input_test_archive: "30",
      input_test_plain: "typed",
      input_test_on: "2026-03-01",
      input_test_unit: "box",
      input_test_steps: '["First","Second"]'
    }
    saved.each { |key, text| Settings.set(key, text) }
    sign_in @admin_user

    post update_settings_path, params: { settings: page_params }

    assert_redirected_to settings_path
    saved.each { |key, text| assert_equal text, Settings[key], key }
  end

  test "saving changed pickers writes the text format" do
    Settings.set(:input_test_grants, "Trip Lead > Alpha Team\nOld Badge")
    sign_in @admin_user

    changed = page_params.deep_merge(
      input_test_teams: { values: [ "", "Alpha Team", "Beta Team" ] },
      input_test_grants: { rows: { "1" => { remove: "1" }, "2" => { badge: "Trip Lead", team: "Beta Team" } } },
      input_test_kinds: { values: [ "", "used", "counted" ] },
      input_test_notice: "off",
      input_test_domains: { items: [ "", "x.com", "", "z.com" ] },
      input_test_start: { month: "5", day: "1" },
      input_test_archive: { mode: "date", date: "2026-07-01", days: "" },
      input_test_on: "2026-04-15",
      input_test_unit: "metre",
      input_test_steps: { names: [ "Second", "Third", "" ] }
    )
    post update_settings_path, params: { settings: changed }

    assert_equal "Alpha Team\nBeta Team", Settings[:input_test_teams]
    assert_equal "Trip Lead > Alpha Team\nTrip Lead > Beta Team", Settings[:input_test_grants]
    assert_equal "used, counted", Settings[:input_test_kinds]
    assert_equal "off", Settings[:input_test_notice]
    assert_equal "x.com, z.com", Settings[:input_test_domains]
    assert_equal "05-01", Settings[:input_test_start]
    assert_equal "2026-07-01", Settings[:input_test_archive]
    assert_equal "2026-04-15", Settings[:input_test_on]
    assert_equal "metre", Settings[:input_test_unit]
    assert_equal '["Second","Third"]', Settings[:input_test_steps]
  end

  test "a blank select stays blank when the page is saved" do
    Settings.set(:input_test_notice, "")
    sign_in @admin_user

    get settings_path
    assert_select "select[name='settings[input_test_notice]'] option[selected][value='']", text: "Not set"

    post update_settings_path, params: { settings: { input_test_notice: "", input_test_plain: "changed" } }

    assert_equal "", Settings[:input_test_notice]
    assert_equal "changed", Settings[:input_test_plain]
  end

  test "a field that doesn't show its value keeps it when left blank" do
    Settings.set(:input_test_token, "kept")
    sign_in @admin_user

    post update_settings_path, params: { keep_if_blank: [ "input_test_token" ], settings: { input_test_token: "" } }
    assert_equal "kept", Settings[:input_test_token]

    post update_settings_path, params: { keep_if_blank: [ "input_test_token" ], settings: { input_test_token: "new" } }
    assert_equal "new", Settings[:input_test_token]
  end

  test "a not found line is kept unless removed" do
    Settings.set(:input_test_grants, "Old Badge")
    Settings.set(:input_test_teams, "Gone Team")
    sign_in @admin_user

    post update_settings_path, params: { settings: {
      input_test_grants: { rows: { "0" => { line: "Old Badge" } } },
      input_test_teams: { values: [ "", "Gone Team" ] }
    } }
    assert_equal "Old Badge", Settings[:input_test_grants]
    assert_equal "Gone Team", Settings[:input_test_teams]

    post update_settings_path, params: { settings: {
      input_test_grants: { rows: { "0" => { line: "Old Badge", remove: "1" } } },
      input_test_teams: { values: [ "" ] }
    } }
    assert_equal "", Settings[:input_test_grants]
    assert_equal "", Settings[:input_test_teams]
  end

  test "a value shown as saved is saved as typed" do
    Settings.set(:input_test_start, "spring")
    sign_in @admin_user

    post update_settings_path, params: { settings: { input_test_start: "06-01" } }

    assert_equal "06-01", Settings[:input_test_start]
  end

  test "members can't save settings" do
    sign_in @member_user

    post update_settings_path, params: { settings: { input_test_notice: "off" } }

    assert_redirected_to root_path
    assert_equal "daily", Settings[:input_test_notice]
  end

  # --- a feature's own settings page -----------------------------------------

  test "saving returns to a local return path" do
    sign_in @admin_user

    post update_settings_path, params: { return_to: "/teams?x=1", settings: { input_test_notice: "off" } }

    assert_redirected_to "/teams?x=1"
    assert_equal "off", Settings[:input_test_notice]
  end

  test "any other return path goes back to the settings page" do
    sign_in @admin_user

    [ "https://example.com/teams", "//example.com/teams", "/\\example.com" ].each do |path|
      post update_settings_path, params: { return_to: path, settings: { input_test_notice: "off" } }

      assert_redirected_to settings_path
    end
  end

  test "a badge grant input can say what a grant with no team means" do
    Settings.input(:input_test_grants, :badge_grants, blank_team_label: "Up to: every team")
    sign_in @admin_user
    get settings_path
    assert_select "select[name$='[team]'] option[value='']", text: "Up to: every team"
  ensure
    Settings.input(:input_test_grants, :badge_grants)
  end
end
