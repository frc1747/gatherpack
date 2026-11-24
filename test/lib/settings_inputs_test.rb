require "test_helper"

class SettingsInputsTest < ActiveSupport::TestCase
  setup do
    @path = Rails.root.join("tmp", "settings-inputs-test-#{Process.pid}.pstore").to_s
    File.delete(@path) if File.exist?(@path)
    @original_store = Settings.instance.store
    Settings.instance.store = PStore.new(@path, true)
    @original_inputs = Settings.instance.inputs.dup
    @original_pages = Settings.instance.pages.dup
    @original_settings = Settings.instance.settings.dup

    Settings.register(:input_test_teams, :text, "Teams", "", "Input Tests", "")
    Settings.register(:input_test_grants, :text, "Grants", "", "Input Tests", "")
    Settings.register(:input_test_kinds, :string, "Kinds", "used, moved", "Input Tests", "")
    Settings.register(:input_test_notice, :string, "Notice", "daily", "Input Tests", "")
    Settings.register(:input_test_domains, :string, "Domains", "a.com, b.com", "Input Tests", "")
    Settings.register(:input_test_start, :string, "Start", "05-01", "Input Tests", "")
    Settings.register(:input_test_archive, :string, "Archive", "", "Input Tests", "")
    Settings.register(:input_test_on, :string, "On", "", "Input Tests", "")
    Settings.register(:input_test_steps, :text, "Steps", "[]", "Input Tests", "")

    Settings.input(:input_test_teams, :teams)
    Settings.input(:input_test_grants, :badge_grants)
    Settings.input(:input_test_kinds, :checkboxes, choices: [ [ "Used", "used" ], [ "Moved", "moved" ], [ "Take off", "take_off" ] ])
    Settings.input(:input_test_notice, :select, choices: [ [ "Off", "off" ], [ "Each time", "each" ], [ "Daily", "daily" ] ])
    Settings.input(:input_test_domains, :list)
    Settings.input(:input_test_start, :month_day)
    Settings.input(:input_test_archive, :date_or_days)
    Settings.input(:input_test_on, :date)
    Settings.input(:input_test_steps, :partial, partial: "test/steps", to_text: ->(posted, _current) { JSON.generate(Array(posted[:names]).compact_blank) })

    @badge = Badge.create!(name: "Trip Lead", color: "blue", short: "TL", badge_type: badge_types(:one))
  end

  teardown do
    Settings.instance.store = @original_store
    Settings.instance.inputs.replace(@original_inputs)
    Settings.instance.pages.replace(@original_pages)
    Settings.instance.settings.replace(@original_settings)
    File.delete(@path) if File.exist?(@path)
  end

  def input(key)
    SettingInput.for(key)
  end

  # --- registry ------------------------------------------------------------

  test "input records how to draw a setting" do
    registered = Settings.input_for(:input_test_teams)

    assert_equal :teams, registered.kind
    assert_instance_of SettingInput::Teams, input(:input_test_teams)
    assert_equal "settings/inputs/teams", input(:input_test_teams).to_partial_path
  end

  test "a setting without an input has none" do
    assert_nil Settings.input_for(:title)
    assert_nil SettingInput.for(:title)
  end

  test "an unknown kind is refused" do
    assert_raises(ArgumentError) { Settings.input(:input_test_teams, :sliders) }
  end

  test "page records a group shown on its own page" do
    Settings.page("Input Tests", :root_path, label: "Set it up")

    page = Settings.page_for("Input Tests")
    assert_equal :root_path, page.path
    assert_equal "Set it up", page.label
    assert_nil Settings.page_for("Site Settings")
  end

  test "a page whose condition is false isn't used" do
    shown = false
    Settings.page("Input Tests", :root_path, if: -> { shown })

    assert_nil Settings.page_for("Input Tests")
    shown = true
    assert_equal :root_path, Settings.page_for("Input Tests").path
  end

  # --- teams ---------------------------------------------------------------

  test "teams keep saved names in order and add new ones" do
    Settings.set(:input_test_teams, "Beta Team\r\nAlpha Team")

    text = input(:input_test_teams).text_from({ values: [ "", "Alpha Team", "Beta Team" ] })
    assert_equal "Beta Team\r\nAlpha Team", text, "an unchanged value keeps its exact text"

    text = input(:input_test_teams).text_from({ values: [ "", "Beta Team" ] })
    assert_equal "Beta Team", text

    Settings.set(:input_test_teams, "Beta Team")
    text = input(:input_test_teams).text_from({ values: [ "", "Alpha Team", "Beta Team" ] })
    assert_equal "Beta Team\nAlpha Team", text
  end

  test "a team that no longer exists shows as not found" do
    Settings.set(:input_test_teams, "Gone Team\nAlpha Team")

    missing = input(:input_test_teams).entries.select(&:missing)
    assert_equal [ "Not found: Gone Team" ], missing.map(&:label)
    assert missing.first.checked
  end

  test "teams sharing a name are one choice labelled with their paths" do
    Team.create!(name: "Alpha Team", team_type: team_types(:one), parent: teams(:two))

    choices = input(:input_test_teams).choices.select { |_, name| name == "Alpha Team" }
    assert_equal [ [ "Alpha Team (Alpha Team, Beta Team › Alpha Team)", "Alpha Team" ] ], choices
  end

  test "clearing every team saves blank" do
    Settings.set(:input_test_teams, "Alpha Team")

    assert_equal "", input(:input_test_teams).text_from({ values: [ "" ] })
  end

  # --- checkboxes ----------------------------------------------------------

  test "checkboxes save the same comma list" do
    Settings.set(:input_test_kinds, "Moved, used")

    assert_equal "Moved, used", input(:input_test_kinds).text_from({ values: [ "", "used", "moved" ] })
    assert_equal "Moved, used, take_off", input(:input_test_kinds).text_from({ values: [ "", "used", "moved", "take_off" ] })
    assert_equal "used", input(:input_test_kinds).text_from({ values: [ "", "used" ] })
  end

  test "an unknown word stays checked until unchecked" do
    Settings.set(:input_test_kinds, "used, flown")

    entry = input(:input_test_kinds).entries.find(&:missing)
    assert_equal "Not found: flown", entry.label
    assert_equal "used, flown", input(:input_test_kinds).text_from({ values: [ "", "used", "flown" ] })
    assert_equal "used", input(:input_test_kinds).text_from({ values: [ "", "used" ] })
  end

  test "checkboxes describe their default with labels" do
    assert_equal "Used, Moved", input(:input_test_kinds).default_label
  end

  # --- badge grants --------------------------------------------------------

  test "the grant line format reads and writes the same lines" do
    assert_equal [ "Trip Lead", "Alpha Team" ], SettingInput::BadgeGrants.parse_line(" Trip Lead >  Alpha Team ")
    assert_equal [ "Trip Lead", nil ], SettingInput::BadgeGrants.parse_line("Trip Lead")
    assert_nil SettingInput::BadgeGrants.parse_line("  ")
    assert_equal "Trip Lead > Alpha Team", SettingInput::BadgeGrants.format_line("Trip Lead", "Alpha Team")
    assert_equal "Trip Lead", SettingInput::BadgeGrants.format_line("Trip Lead", "")
  end

  test "grant rows load saved lines and mark the ones not found" do
    Settings.set(:input_test_grants, "trip lead > Alpha Team\nTrip Lead\nOld Badge > Alpha Team\nTrip Lead > Gone Team")

    rows = input(:input_test_grants).rows
    assert_equal [ "Trip Lead", "Alpha Team" ], [ rows[0].badge_name, rows[0].team_name ]
    assert_equal [ "Trip Lead", nil ], [ rows[1].badge_name, rows[1].team_name ]
    assert_equal [ false, false, true, true ], rows.map(&:missing)
  end

  test "grant rows save the same lines" do
    current = "trip lead > Alpha Team\nOld Badge > Alpha Team"
    Settings.set(:input_test_grants, current)

    unchanged = {
      rows: {
        "0" => { line: "trip lead > Alpha Team", badge: "Trip Lead", team: "Alpha Team" },
        "1" => { line: "Old Badge > Alpha Team" },
        "2" => { line: "", badge: "", team: "" }
      }
    }
    assert_equal current, input(:input_test_grants).text_from(unchanged)

    changed = {
      rows: {
        "0" => { line: "trip lead > Alpha Team", badge: "Trip Lead", team: "" },
        "1" => { line: "Old Badge > Alpha Team", remove: "1" },
        "2" => { line: "", badge: "Trip Lead", team: "Beta Team" }
      }
    }
    assert_equal "Trip Lead\nTrip Lead > Beta Team", input(:input_test_grants).text_from(changed)
  end

  test "a not found grant is kept unless removed" do
    Settings.set(:input_test_grants, "Old Badge > Alpha Team")

    kept = { rows: { "0" => { line: "Old Badge > Alpha Team" }, "1" => { line: "", badge: "Trip Lead", team: "" } } }
    assert_equal "Old Badge > Alpha Team\nTrip Lead", input(:input_test_grants).text_from(kept)

    removed = { rows: { "0" => { line: "Old Badge > Alpha Team", remove: "1" } } }
    assert_equal "", input(:input_test_grants).text_from(removed)
  end

  test "badges: limits the badges offered" do
    Settings.input(:input_test_grants, :badge_grants, badges: -> { Badge.where(name: "Trip Lead") })

    assert_equal [ "Trip Lead" ], input(:input_test_grants).badges.map(&:name)
  end

  # --- select, list, text, dates, partial -----------------------------------

  test "select offers a saved value that isn't a choice" do
    Settings.set(:input_test_notice, "weekly")

    assert_includes input(:input_test_notice).choices, [ "Not found: weekly", "weekly" ]
    assert_equal "each", input(:input_test_notice).text_from("each")
    assert_equal "Daily", input(:input_test_notice).default_label
  end

  test "select keeps a blank value blank" do
    Settings.set(:input_test_notice, "")

    assert_equal [ "Not set", "" ], input(:input_test_notice).choices.last
    assert_equal "", input(:input_test_notice).selected_value
    assert_equal "", input(:input_test_notice).text_from("")
  end

  test "select matches choices ignoring case" do
    Settings.set(:input_test_notice, "Daily")

    assert_equal "daily", input(:input_test_notice).selected_value
    assert_not input(:input_test_notice).choices.any? { |label, _| label.start_with?("Not found") }
    assert_equal "Daily", input(:input_test_notice).text_from("daily"), "an unchanged value keeps its text"
  end

  test "list saves entries joined as before" do
    Settings.set(:input_test_domains, "a.com,b.com")

    assert_equal "a.com,b.com", input(:input_test_domains).text_from({ items: [ "", "a.com", "b.com", "" ] })
    assert_equal "a.com, c.com", input(:input_test_domains).text_from({ items: [ "", "a.com", " ", "c.com" ] })
  end

  test "text suggests values" do
    Settings.register(:input_test_unit, :string, "Unit", "each", "Input Tests", "")
    Settings.input(:input_test_unit, :text, suggestions: -> { %w[each box] })

    assert_equal %w[each box], input(:input_test_unit).suggestions
    assert_equal "metre", input(:input_test_unit).text_from("metre")
  end

  test "month and day save as MM-DD" do
    Settings.set(:input_test_start, "05-01")

    assert_equal [ 5, 1 ], [ input(:input_test_start).month, input(:input_test_start).day ]
    assert_equal "05-01", input(:input_test_start).text_from({ month: "5", day: "1" })
    assert_equal "09-15", input(:input_test_start).text_from({ month: "9", day: "15" })
    assert_equal "", input(:input_test_start).text_from({ month: "", day: "15" })
    assert_equal "May 1", input(:input_test_start).default_label
  end

  test "a value the picker can't read isn't readable" do
    Settings.set(:input_test_start, "spring")
    assert_not input(:input_test_start).readable?

    Settings.set(:input_test_on, "2026-02-30")
    assert_not input(:input_test_on).readable?

    Settings.set(:input_test_archive, "soon")
    assert_not input(:input_test_archive).readable?
  end

  test "date or days saves a date, a number of days, or blank" do
    archive = input(:input_test_archive)

    assert_equal "", archive.text_from({ mode: "never", date: "2026-01-01", days: "30" })
    assert_equal "2026-01-01", archive.text_from({ mode: "date", date: "2026-01-01", days: "30" })
    assert_equal "30", archive.text_from({ mode: "days", date: "", days: "030" })
    assert_equal "Never", archive.default_label

    Settings.set(:input_test_archive, "45")
    assert_equal [ "days", "45" ], [ input(:input_test_archive).mode, input(:input_test_archive).days ]
  end

  test "a partial input saves through its to_text" do
    assert_equal '["One","Two"]', input(:input_test_steps).text_from({ names: [ "One", "", "Two" ] })
    assert_equal "test/steps", input(:input_test_steps).to_partial_path
    assert_equal "See the field", input(:input_test_steps).default_label
  end

  # --- return path -----------------------------------------------------------

  test "only a path on this site is a return path" do
    assert_equal "/teams/setup", SettingInputParams.local_path("/teams/setup")
    assert_equal "/teams/setup?tab=1", SettingInputParams.local_path("/teams/setup?tab=1")

    [ "https://example.com/", "//example.com/x", "/\\example.com", "javascript:alert(1)", "teams", "", nil, "/a b" ].each do |path|
      assert_nil SettingInputParams.local_path(path), "#{path.inspect} should be refused"
    end
  end
end
