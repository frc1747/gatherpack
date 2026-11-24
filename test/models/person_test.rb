require "test_helper"

class PersonTest < ActiveSupport::TestCase
  setup do
    @org = Team.create!(name: "Org", team_type: team_types(:one))
    @pack = Team.create!(name: "Pack", team_type: team_types(:one), parent: @org)
    @den = Team.create!(name: "Den A", team_type: team_types(:one), parent: @pack)
    @person = Person.create!(first_name: "Dana", last_name: "Den")
  end

  test "all_ancestor_team_ids returns unique id strings for direct and ancestor teams" do
    Membership.create!(person: @person, team: @den)
    Membership.create!(person: @person, team: @pack)

    ids = @person.all_ancestor_team_ids
    assert ids.all?(String)
    assert_equal [ @den.id, @pack.id, @org.id ].sort, ids.sort
    assert_includes ids, @pack.id
  end

  test "all_team_ids returns id strings without duplicates" do
    Membership.create!(person: @person, team: @den)
    Membership.create!(person: @person, team: @pack)

    ids = @person.all_team_ids
    assert ids.all?(String)
    assert_equal [ @den.id, @pack.id, @org.id ].sort, ids.sort
    assert_equal ids.uniq, ids
    assert_includes ids, @org.id
  end

  test "all_team_ids includes teams below a managed team" do
    Membership.create!(person: @person, team: @pack, manager: true)

    ids = @person.all_team_ids
    assert ids.all?(String)
    assert_includes ids, @den.id
    assert_includes ids, @pack.id
    assert_includes ids, @org.id
  end
end
