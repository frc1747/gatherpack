require "test_helper"
require_relative "../support/checklists_world"

# The checklist settings are drawn as pickers on the Settings page where the
# settings-inputs seam is merged, and keep their saved text exactly.
class ChecklistSettingsPickersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  KEYS = %i[checklists_organizers checklists_archive_after checklists_prune_results_after].freeze

  setup do
    host! "localhost"
    build_checklists_world
  end

  test "the settings are registered without the picker seam" do
    KEYS.each { |key| assert Settings.get(key), key }
    assert_no_match(/Badge name >|YYYY-MM-DD/, Settings.get(:checklists_organizers).description + Settings.get(:checklists_archive_after).description)
  end

  test "each setting has a picker" do
    skip "needs Settings.input" unless Settings.respond_to?(:input)

    assert_equal :badge_grants, Settings.input_for(:checklists_organizers).kind
    assert_equal :date_or_days, Settings.input_for(:checklists_archive_after).kind
    assert_equal :date_or_days, Settings.input_for(:checklists_prune_results_after).kind
  end

  test "the pickers show the saved values" do
    skip "needs Settings.input" unless Settings.respond_to?(:input)

    with_settings(checklists_organizers: "Checklist Organizer > Club", checklists_archive_after: "30", checklists_prune_results_after: "2026-03-01") do
      sign_in person(:admin).user
      get settings_path

      assert_response :success
      assert_select "select[name='settings[checklists_organizers][rows][0][badge]'] option[selected]", text: "Checklist Organizer"
      assert_select "select[name='settings[checklists_organizers][rows][0][team]'] option[selected]", text: "Club"
      assert_select "input[type=radio][name='settings[checklists_archive_after][mode]'][value='days'][checked]"
      assert_select "input[name='settings[checklists_archive_after][days]'][value='30']"
      assert_select "input[type=radio][name='settings[checklists_prune_results_after][mode]'][value='date'][checked]"
      assert_select "input[type=date][name='settings[checklists_prune_results_after][date]'][value='2026-03-01']"
    end
  end

  test "saving the Settings page unchanged keeps the exact text" do
    skip "needs Settings.input" unless Settings.respond_to?(:input)

    saved = { checklists_organizers: "Checklist Organizer > Club\r\nHelper", checklists_archive_after: "30", checklists_prune_results_after: "2026-03-01" }
    with_settings(saved) do
      sign_in person(:admin).user
      get settings_path
      post update_settings_path, params: { settings: posted_values(KEYS) }

      saved.each { |key, text| assert_equal text, Settings[key], key }
    end
  end

  test "blank values stay blank on a round trip" do
    skip "needs Settings.input" unless Settings.respond_to?(:input)

    with_settings(checklists_organizers: "", checklists_archive_after: "", checklists_prune_results_after: "") do
      sign_in person(:admin).user
      get settings_path
      post update_settings_path, params: { settings: posted_values(KEYS) }

      KEYS.each { |key| assert_equal "", Settings[key].to_s, key }
    end
  end

  private

  # What the browser would post for these settings: every named field on the
  # page, with the selected option and the checked boxes and radios.
  def posted_values(keys)
    form = Nokogiri::HTML(response.body)
    pairs = form.css("input, select").filter_map do |field|
      name = field["name"]
      next unless name&.start_with?(*keys.map { |key| "settings[#{key}]" })

      case field.name
      when "select"
        option = field.at_css("option[selected]") || field.at_css("option")
        [ name, option&.[]("value").to_s ]
      else
        next if %w[radio checkbox].include?(field["type"]) && !field.key?("checked")

        [ name, field["value"].to_s ]
      end
    end
    Rack::Utils.parse_nested_query(pairs.map { |name, value| "#{Rack::Utils.escape(name)}=#{Rack::Utils.escape(value)}" }.join("&"))["settings"]
  end
end
