require "test_helper"
require_relative "../support/signups_world"

# Other features adding to sign-up pages through Signups.extensions
# (spec §3.9): a panel on the sheet page and hints on on-behalf-of choices.
class SignupExtensionsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SignupsWorld

  setup do
    host! "localhost"
    travel_to Time.zone.parse("2026-10-11 12:00")
    build_signups_world
    @sheet = create_world_sheet(others_relationship_type_ids: [ @parent_of.id ], on_behalf_of_mode: :related_people)
    @slot = slot_for(@sheet.signup_positions.create!(name: "Cashier", capacity: 4))

    @original_extensions = Signups.extensions
    Signups.instance_variable_set(:@extensions, Signups::Extensions.new)
    @original_view_paths = ActionController::Base.view_paths
    ActionController::Base.prepend_view_path(Rails.root.join("test/support/views"))
  end

  teardown do
    Signups.instance_variable_set(:@extensions, @original_extensions)
    ActionController::Base.view_paths = @original_view_paths
  end

  test "a registered panel shows on the sheet page, given the sheet and the viewer" do
    Signups.extensions.register_sheet_panel(:test, partial: "signups_test/sheet_panel")
    sign_in person(:student).user

    get signup_sheet_path(@sheet)

    assert_select "#test_sheet_panel", text: "Snack Stand for Student"
  end

  test "with no panels registered the sheet page is as before" do
    sign_in person(:student).user

    get signup_sheet_path(@sheet)

    assert_response :success
    assert_select "#test_sheet_panel", count: 0
  end

  test "registered hints show next to each on-behalf-of choice" do
    Signups.extensions.register_on_behalf_of_hint(:test, ->(sheet, person) { "#{person.first_name} owes 2 on #{sheet.title}" })
    sign_in person(:parent).user

    get new_signup_sheet_signup_path(@sheet, slot_id: @slot.id)

    assert_select "label", text: "Student World (Student owes 2 on Snack Stand)"
  end

  test "hints show in the on-behalf-of search on sheets open to anyone" do
    @sheet.on_behalf_of_anyone!
    Signups.extensions.register_on_behalf_of_hint(:test, ->(_sheet, person) { "#{person.first_name} owes 1" })
    sign_in person(:student).user

    get new_signup_sheet_signup_path(@sheet, slot_id: @slot.id, q: "StudentTwo"), as: :turbo_stream

    assert_response :success
    assert_match "StudentTwo owes 1", response.body
  end
end
