require "test_helper"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# Per-form options: sharing totals beyond the people who can see answers,
# and a dashboard to-do for leaders.
class FormOptionsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @form = create_world_form("Pizza Night", respond: "family", read: "family")
    @pizza = add_choice(@form, "Pizza", %w[ Cheese Pepperoni ])
    @private = add_choice(@form, "Allergy note", %w[ Nuts None ], read_permission: "self_and_leaders", write_permission: "self")
    respond(@form, :a1, as: :a1, answers: { "pizza" => "Cheese", "allergy_note" => "Nuts" })
    respond(@form, :b1, as: :b1, answers: { "pizza" => "Cheese" })
  end

  test "shared totals show counts to everyone asked, without answers or private questions" do
    with_feature do
      as(:a2) do
        get tally_form_path(@form)
        assert_redirected_to root_path, "by default only people who can see answers get totals"
      end

      @form.update!(totals_visibility: :audience)
      as(:a2) do
        get tally_form_path(@form)
        assert_response :success
        assert_select "h2", text: "Pizza"
        assert_select "td", text: "2"
        assert_select "h2", text: "Allergy note", count: 0
        assert_no_match "A1 World", response.body
      end
      as(:parent_a2) do
        get tally_form_path(@form)
        assert_response :success, "guardians of someone asked see them too"
      end
      as(:outsider) do
        get tally_form_path(@form)
        assert_redirected_to root_path
      end

      @form.update!(totals_visibility: :everyone)
      as(:outsider) do
        get tally_form_path(@form)
        assert_response :success
      end
    end
  end

  test "leaders get a to-do for responses waiting on them, when the form asks for it" do
    add_choice(@form, "Leader check", %w[ OK ], required: true, read_permission: "family", write_permission: "leaders")
    respond(@form, :a2, as: :a2, answers: { "pizza" => "Pepperoni" })

    with_feature do
      as(:den_a_leader) do
        get root_path
        assert_select "h2", text: "Waiting on You as a Leader", count: 0
      end

      @form.update!(leader_todo: true)
      as(:den_a_leader) do
        get root_path
        assert_select "h2", text: "Waiting on You as a Leader"
        assert_select "small", text: /A2 World/
      end
      as(:den_b_leader) do
        get root_path
        assert_select "h2", text: "Waiting on You as a Leader", count: 0
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
