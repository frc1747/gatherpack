require "test_helper"
require_relative "../support/checklists_world"
require_relative "../support/checklists_test_kinds"

# Any setting declared list: true keeps an array of values, of any type.
class ChecklistListSettingsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ChecklistsWorld

  setup do
    host! "localhost"
    Checklists.register_item_kind(:lists, ChecklistsTestKinds::Lists)
    build_checklists_world
    @checklist = create_world_checklist(status: :draft)
  end

  teardown do
    Checklists.unregister_item_kind(:lists)
  end

  private

  # What a browser would post from the form, as [name, value] pairs in
  # order: each named field's value as rendered (ticked boxes and radios,
  # selected options, repeated names kept).
  def rendered_form_pairs(html, selector)
    form = Nokogiri::HTML(html).at_css(selector)
    pairs = []
    form.css("input[name], select[name], textarea[name]").each do |field|
      name = field["name"]
      case field.name
      when "select"
        field.css("option[selected]").each { |option| pairs << [ name, option["value"] ] }
      when "textarea"
        pairs << [ name, field.text ]
      else
        next if %w[checkbox radio].include?(field["type"]) && !field["checked"]
        next if field["type"] == "submit"

        pairs << [ name, field["value"].to_s ]
      end
    end
    pairs
  end

  test "list settings are permitted as arrays and cast per value" do
    assert_equal [ { forms: [] }, { years: [] }, { dates: [] }, { notes: [] }, { others: [] }, :mode ], ChecklistsTestKinds::Lists.permitted_config
    assert_equal({ "forms" => %w[consent photo], "years" => [ 2026, 2027 ], "mode" => "any" },
      ChecklistsTestKinds::Lists.normalize_config({ "forms" => [ "consent", "", "photo" ], "years" => %w[2026 2027], "mode" => "any" }))
    assert Checklists::Kinds::Badge.settings.first.list?, "badges are always a list"
  end

  test "list settings of every built-in type survive opening the item and saving what the form shows" do
    other = create_world_checklist("Other")
    item = @checklist.checklist_items.new(kind: "lists", label: "Lists")
    item.config_params = { forms: %w[consent photo], years: %w[2026 2027], dates: %w[2026-09-01 2027-01-15],
      notes: [ "Bring boots", "Sign in" ], others: [ other.id ], mode: "any" }
    item.save!
    saved = item.reload.config

    with_feature do
      sign_in person(:admin).user
      get edit_checklist_checklist_item_path(@checklist, item)
      assert_response :success
      assert_select "input[name='checklist_item[config][years][]']", 3, "one per value and an empty one"

      pairs = rendered_form_pairs(response.body, "form[action='#{checklist_checklist_item_path(@checklist, item)}']")
      pairs = pairs.map { |name, value| name == "checklist_item[label]" ? [ name, "Renamed" ] : [ name, value ] }
      patch checklist_checklist_item_path(@checklist, item), params: Rack::Utils.parse_nested_query(URI.encode_www_form(pairs))
      assert_response :see_other
    end

    item.reload
    assert_equal "Renamed", item.label
    assert_equal saved, item.config
    assert_equal [ 2026, 2027 ], item.config["years"]
    assert_equal %w[2026-09-01 2027-01-15], item.config["dates"]
    assert_equal [ "Bring boots", "Sign in" ], item.config["notes"]
    assert_equal [ other.id ], item.config["others"]
  end

  test "a kind can't make a boolean or relative date setting a list" do
    kind = Class.new(Checklists::ItemKind) do
      def self.name = "BadKind"
      def self.settings = [ Checklists::ItemKind::Setting.new(key: :flags, type: :boolean, label: "Flags", list: true) ]
    end

    error = assert_raises(ArgumentError) { Checklists.register_item_kind(:bad, kind) }
    assert_match "a boolean setting can't be a list", error.message
    assert_nil Checklists.item_kind(:bad)
  end

  test "the item form posts and saves several values for a list setting" do
    with_feature do
      sign_in person(:admin).user
      get new_checklist_checklist_item_path(@checklist, kind: "lists")
      assert_select "select[multiple][name='checklist_item[config][forms][]']"
      assert_select "select:not([multiple])[name='checklist_item[config][mode]']"

      post checklist_checklist_items_path(@checklist), params: { checklist_item: { kind: "lists", label: "Forms",
        config: { forms: %w[consent medical], years: [ "2026" ], mode: "all" } } }
      item = @checklist.checklist_items.find_by!(label: "Forms")
      assert_equal %w[consent medical], item.config["forms"]
      assert_equal [ 2026 ], item.config["years"]
      assert_equal "all", item.config["mode"]
    end
  end
end
