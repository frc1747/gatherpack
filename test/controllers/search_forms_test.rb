require "test_helper"

class SearchFormsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Index pages whose search form is built with search_form_for. Drawing a
  # field asks Ransack about the model's associations, so each page fails
  # if its model has no ransackable_associations.
  SEARCH_PAGES = %w[
    /announcements /audit_logs /badge_types /badges /budget_periods /budgets
    /checkin_fields /event_types /events /hooks
    /ledger_entry_links /ledger_tags /ledgers /mailboxes /oauth_applications
    /pages /people /questions /relationship_types /reports /shortcuts
    /team_types /teams /time_clock_periods /time_clock_punches /tokens
    /variables
  ].freeze

  setup do
    host! "localhost"
    admin = User.create!(email: "admin@example.com", password: "Password1!", admin: true)
    Person.create!(user: admin, first_name: "Ada", last_name: "Admin")
    sign_in admin
  end

  SEARCH_PAGES.each do |path|
    test "#{path} search page renders" do
      get path

      assert_response :success
    end
  end
end
