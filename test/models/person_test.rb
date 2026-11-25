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

  def build_team(name, parent = nil)
    Team.create!(name: name, team_type: team_types(:one), parent: parent)
  end

  def build_person(name, team: nil, manager: false)
    person = Person.create!(first_name: name, last_name: "Test", display_name: name)
    Membership.create!(person: person, team: team, manager: manager) if team
    person
  end

  test "on_teams finds people with a membership on the given teams" do
    team = build_team("Team")
    other = build_team("Other")
    member = build_person("Member", team: team)
    lead = build_person("Lead", team: team, manager: true)
    outsider = build_person("Outsider", team: other)

    assert_equal [ member, lead ].map(&:id).sort, Person.on_teams([ team.id ]).pluck(:id).sort
    assert_equal [ lead.id ], Person.on_teams([ team.id ], managers: true).pluck(:id)
    assert_equal [ member.id ], Person.on_teams([ team.id ], managers: false).pluck(:id)
    assert_equal [ outsider.id ], Person.on_teams(other.id).pluck(:id)
    assert_empty Person.on_teams([])
  end

  test "on_teams lists a person on several teams once and chains" do
    a = build_team("A")
    b = build_team("B")
    person = build_person("Both", team: a)
    Membership.create!(person: person, team: b)

    assert_equal 1, Person.on_teams([ a.id, b.id ]).count
    assert_equal [ person.id ], Person.on_teams([ a.id, b.id ]).where(first_name: "Both").pluck(:id)
  end

  test "visible_to gives an admin everyone" do
    admin = people(:one)
    admin.user.update!(admin: true)

    assert_equal Person.count, Person.visible_to(admin).count
  end

  test "visible_to matches the people list policy scope" do
    root = build_team("Root")
    left = build_team("Left", root)
    left_leaf = build_team("Left leaf", left)
    right = build_team("Right", root)
    unrelated = build_team("Unrelated")

    viewers = [
      build_person("Root lead", team: root, manager: true),
      build_person("Left member", team: left),
      build_person("Left lead", team: left, manager: true),
      build_person("Leaf member", team: left_leaf),
      build_person("Right member", team: right),
      build_person("Unrelated member", team: unrelated),
      build_person("No team")
    ]
    Membership.create!(person: viewers[1], team: right) # on two sibling branches

    (viewers + Person.all.to_a).uniq.each do |viewer|
      next unless viewer.user.nil? || !viewer.user.admin?
      viewer.user ||= User.create!(email: "#{viewer.id}@example.com", password: "password123")
      viewer.save!
      expected = PersonPolicy::Scope.new(viewer.user, Person).resolve.pluck(:id).sort

      assert_equal expected, Person.visible_to(viewer).pluck(:id).sort, viewer.display_name
    end
  end

  test "visible_to uses a bounded number of queries however deep the tree" do
    root = build_team("Root")
    team = root
    20.times { |i| team = build_team("Level #{i}", team) }
    viewer = build_person("Root lead", team: root, manager: true)
    leaf_viewer = build_person("Leaf member", team: team)
    [ viewer, leaf_viewer ].each { |v| v.update!(user: User.create!(email: "#{v.id}@example.com", password: "password123")) }

    [ viewer, leaf_viewer ].each do |v|
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { Person.visible_to(v).load }

      assert_operator queries.size, :<=, 4, queries.join("\n")
    end
  end
end
