require "test_helper"
require_relative "../support/settings_test_helper"

class FormsGuardianGrantsTest < ActiveSupport::TestCase
  include SettingsTestHelper

  test "the forms lines are listed only while forms is on" do
    with_settings(feature_forms: "true") do
      assert_includes RelationshipType.guardian_grants, "fill in forms for the child and sign consent as their guardian"
      assert_includes RelationshipType.guardian_grants, "get form reminders about the child"
    end

    with_settings(feature_forms: "false") do
      assert_not_includes RelationshipType.guardian_grants, "fill in forms for the child and sign consent as their guardian"
      assert_not_includes RelationshipType.guardian_grants, "get form reminders about the child"
    end
  end
end
