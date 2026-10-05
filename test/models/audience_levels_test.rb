require "test_helper"

class AudienceLevelsTest < ActiveSupport::TestCase
  test "every level has a stored value" do
    assert_equal AudienceLevels::PERMISSION_LEVELS.keys.sort, AudienceLevels::LEVEL_VALUES.keys.map(&:to_s).sort
  end

  test "everyone reaches every component" do
    %i[ subject guardian leaders teammates everyone ].each do |component|
      assert AudienceLevels.reaches?("everyone", component)
    end
    assert_not AudienceLevels.reaches?("family", :teammates)
    assert AudienceLevels.reaches?("family", :guardian)
  end

  test "within compares levels as sets of components" do
    assert AudienceLevels.within?("self_and_leaders", "family")
    assert AudienceLevels.within?("admin", "self")
    assert AudienceLevels.within?("everyone", "everyone")
    assert AudienceLevels.within?("team", "everyone")
    assert_not AudienceLevels.within?("family", "self_and_leaders")
    assert_not AudienceLevels.within?("everyone", "team")
    assert_not AudienceLevels.within?("self", "guardians")
  end
end
