require "test_helper"

class PersonTest < ActiveSupport::TestCase
  test "destroying a person destroys their login" do
    user = User.create!(email: "leaving@example.com", password: "Password1!", admin: true)
    person = Person.create!(user: user, first_name: "Les", last_name: "Leaving")

    person.destroy!

    assert_not User.exists?(user.id), "the deleted person's login still exists"
  end

  test "destroying a person removes their login's OAuth grants and tokens" do
    user = User.create!(email: "leaving@example.com", password: "Password1!")
    person = Person.create!(user: user, first_name: "Les", last_name: "Leaving")
    application = oauth_applications(:one)
    Doorkeeper::AccessToken.create!(application: application, resource_owner_id: user.id)
    Doorkeeper::AccessGrant.create!(application: application, resource_owner_id: user.id,
      redirect_uri: "urn:ietf:wg:oauth:2.0:oob", expires_in: 600)

    person.destroy!

    assert_not User.exists?(user.id)
    assert_not Doorkeeper::AccessToken.exists?(resource_owner_id: user.id)
    assert_not Doorkeeper::AccessGrant.exists?(resource_owner_id: user.id)
  end

  test "destroying a person keeps a login another person still uses" do
    user = User.create!(email: "shared@example.com", password: "Password1!")
    owner = Person.create!(user: user, first_name: "Olive", last_name: "Owner")
    duplicate = Person.create!(user: user, first_name: "Olive", last_name: "Duplicate")

    duplicate.destroy!

    assert User.exists?(user.id), "destroying one person destroyed a login another person still uses"
    assert_equal user, owner.reload.user
  end

  test "destroying a person without a login" do
    person = Person.create!(first_name: "Nora", last_name: "Nologin")

    assert_difference -> { Person.count }, -1 do
      person.destroy!
    end
  end

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
