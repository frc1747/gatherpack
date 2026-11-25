require "test_helper"
require "csv"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# Download CSV carries the results table's heading filters and sort
# (tf, tf_sort, tf_dir), so the file holds the rows left on screen.
class FormResultsFiltersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  setup do
    host! "localhost"
    build_person_fields_world
    @form = create_world_form("Lunch", respond: "self_and_leaders")
    @sandwich = add_choice(@form, "Sandwich", [ "Slim 1", "Slim 4", "Big John" ])
    respond(@form, :a1, as: :a1, answers: { @sandwich.key => "Slim 4" })
    respond(@form, :a2, as: :a2, answers: { @sandwich.key => "Slim 4" })
    respond(@form, :b1, as: :b1, answers: { @sandwich.key => "Big John" })
    sign_in person(:pack_leader).user
  end

  test "a CSV with heading filters has only the matching rows, in the carried sort" do
    with_settings(feature_forms: "true") do
      get form_path(@form, format: :csv, tf: { @sandwich.id => "Slim 4" }, tf_sort: "Person", tf_dir: "desc")
      assert_response :success
      assert_equal [ "A2", "A1" ], first_names

      get form_path(@form, format: :csv, tf: { @sandwich.id => [ "Slim 4", "Big John" ] }, tf_sort: @sandwich.id, tf_dir: "asc")
      assert_equal [ "B1", "A1", "A2" ], first_names, "Big John before Slim 4; ties keep the report's order"

      get form_path(@form, format: :csv, tf: { "status" => "Complete", @sandwich.id => "Big John" })
      assert_equal [ "B1" ], first_names, "filters on several columns combine"

      get form_path(@form, format: :csv, tf: { @sandwich.id => "" })
      assert_not_includes first_names, "A1", "blank picks the people with no answer"
      assert_includes first_names, "PackLeader"
    end
  end

  test "renamed questions keep their filters, since headings are keyed by id" do
    with_settings(feature_forms: "true") do
      get form_path(@form)
      assert_select "#responses th[data-column-key=?]", @sandwich.id, text: "Sandwich"
      assert_select "#responses th[data-column-key=status]", text: "Status"
      assert_select "#responses th[data-column-key=submitted]", text: "Submitted"

      @sandwich.update!(label: "Lunch [main]")
      get form_path(@form, format: :csv, tf: { @sandwich.id => "Big John" })
      assert_equal [ "B1" ], first_names
    end
  end

  test "a CSV without carried params is unchanged" do
    with_settings(feature_forms: "true") do
      get form_path(@form, format: :csv)
      plain = response.body
      get form_path(@form, format: :csv, tf_sort: "Nothing here", tf: { "Unknown" => "x" })
      assert_equal plain, response.body, "unknown keys are ignored"
      assert_includes first_names, "B1"
    end
  end

  test "malformed filters don't error" do
    with_settings(feature_forms: "true") do
      get form_path(@form, format: :csv)
      plain = response.body
      [ "tf=x", "tf[]=x", "tf_sort[]=x&tf_dir=desc", "tf[#{@sandwich.id}][x]=y" ].each do |query|
        get "#{form_path(@form, format: :csv)}?#{query}"
        assert_response :success, query
      end
      get "#{form_path(@form, format: :csv)}?tf=x"
      assert_equal plain, response.body
    end
  end

  test "an answer the viewer can't see filters as the dot the table shows" do
    with_settings(feature_forms: "true", feature_person_fields: "true") do
      secret = create_world_field("Secret", read: "admin")
      question = add_profile_question(@form, secret, :prefill)
      sign_in person(:den_a_leader).user
      get form_path(@form, format: :csv, tf: { question.id => "·" })
      assert_response :success
      assert_includes first_names, "A1"
    end
  end

  test "the totals on the form page list who each count covers" do
    with_settings(feature_forms: "true") do
      get form_path(@form)
      slim = css_select("#totals tr").detect { |row| row.text.include?("Slim 4") }.css("td").last
      assert_equal "2", slim.text
      assert_equal [ person(:a1), person(:a2) ].map { |p| ActionView::RecordIdentifier.dom_id(p) }.sort, slim["data-people"].split.sort
      assert_select "#labels [data-form-results-target=label][data-person=?]", ActionView::RecordIdentifier.dom_id(person(:b1))
    end
  end

  private

  def first_names
    CSV.parse(response.body).drop(1).map { |row| row[1] }
  end
end
