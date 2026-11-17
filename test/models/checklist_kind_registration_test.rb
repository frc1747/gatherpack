require "test_helper"

# Kinds register from initializers, while the app boots, so registering one
# (which reads its settings) must not touch the database: on a fresh one the
# tables don't exist yet and db:schema:load couldn't run. Choices read from
# the database go in a lambda (ItemKind::Setting options), read when the
# form is drawn. Covers every kind registered on the branch.
class ChecklistKindRegistrationTest < ActiveSupport::TestCase
  test "registering every kind, and reading its settings, runs no queries" do
    kinds = Checklists.item_kinds
    assert_not_empty kinds

    queries = []
    counter = ->(*, payload) { queries << payload[:sql] unless payload[:name].in?(%w[SCHEMA TRANSACTION]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      kinds.each do |key, kind|
        Checklists.register_item_kind(key, kind)
        kind.settings.each(&:list?)
      end
    end

    assert_empty queries
  end

  test "a setting's options may be a lambda, read each time" do
    calls = 0
    setting = Checklists::ItemKind::Setting.new(key: :pick, type: :choice, options: -> { calls += 1; [ [ "One", "1" ] ] })

    assert_equal 0, calls
    assert_equal [ [ "One", "1" ] ], setting.options
    assert_equal 1, calls
  end
end
