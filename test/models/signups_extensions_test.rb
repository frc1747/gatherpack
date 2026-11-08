require "test_helper"

# The registry other features use to add to sign-up pages (spec §3.9).
class SignupsExtensionsTest < ActiveSupport::TestCase
  setup do
    @extensions = Signups::Extensions.new
  end

  test "sheet panels are registered by key, and registering a key again replaces it" do
    @extensions.register_sheet_panel(:commitments, partial: "commitments/sheet_panel")
    @extensions.register_sheet_panel("commitments", partial: "commitments/other_panel")
    @extensions.register_sheet_panel(:notes, partial: "notes/panel")

    assert_equal [ "commitments/other_panel", "notes/panel" ], @extensions.sheet_panels.map(&:partial)
  end

  test "on-behalf-of hints are joined, leaving out blank ones" do
    @extensions.register_on_behalf_of_hint(:owed, ->(sheet, person) { "#{person} owes 2 for #{sheet}" })
    @extensions.register_on_behalf_of_hint(:nothing, ->(_sheet, _person) { nil })
    @extensions.register_on_behalf_of_hint(:badge, ->(_sheet, _person) { "has the badge" })

    assert_equal "Ann owes 2 for Snacks; has the badge", @extensions.on_behalf_of_hint("Snacks", "Ann")
  end

  test "with nothing registered there's no hint" do
    assert_nil @extensions.on_behalf_of_hint("Snacks", "Ann")
    assert_empty @extensions.sheet_panels
  end

  test "Signups.extensions is one shared registry" do
    assert_same Signups.extensions, Signups.extensions
  end
end
