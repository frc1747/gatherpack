require "test_helper"

class TokenPolicyTest < ActiveSupport::TestCase
  setup do
    # Pack
    # ├── Den (run by @manager, with @member and @plain_admin as members)
    # └── Other Den (@outsider)
    @pack = Team.create!(name: "Pack", team_type: team_types(:one))
    @den = Team.create!(name: "Den", team_type: team_types(:one), parent: @pack)
    @other_den = Team.create!(name: "Other Den", team_type: team_types(:one), parent: @pack)

    @admin_user, @admin = create_person("admin", admin: true)
    @manager_user, @manager = create_person("manager", team: @den, manager: true)
    @member_user, @member = create_person("member", team: @den)
    _, @outsider = create_person("outsider", team: @other_den)
    _, @plain_admin = create_person("plain-admin", team: @den, admin: true)
    _, @pack_leader = create_person("pack-leader", team: @pack, manager: true)
    Membership.create!(person: @pack_leader, team: @den)
  end

  # --- new? ---------------------------------------------------------------

  test "an admin may open the new card form" do
    assert TokenPolicy.new(@admin_user, Token).new?
  end

  test "a manager may open the new card form" do
    assert TokenPolicy.new(@manager_user, Token).new?
  end

  test "a plain member may not open the new card form" do
    assert_not TokenPolicy.new(@member_user, Token).new?
  end

  # --- create? / update? / destroy? ---------------------------------------

  test "an admin may issue a card to anyone" do
    assert TokenPolicy.new(@admin_user, Token.new(tokenable: @outsider)).create?
    assert TokenPolicy.new(@admin_user, Token.new(tokenable: @plain_admin)).create?
    assert TokenPolicy.new(@admin_user, Token.new).create?
  end

  test "a manager may issue a card to a member they manage" do
    assert TokenPolicy.new(@manager_user, Token.new(tokenable: @member)).create?
  end

  test "a manager may issue a card to themselves" do
    assert TokenPolicy.new(@manager_user, Token.new(tokenable: @manager)).create?
  end

  test "a manager may not issue a card to someone outside their teams" do
    assert_not TokenPolicy.new(@manager_user, Token.new(tokenable: @outsider)).create?
  end

  test "a manager may not issue a card to an admin, even one on their team" do
    assert_not TokenPolicy.new(@manager_user, Token.new(tokenable: @admin)).create?
    assert_not TokenPolicy.new(@manager_user, Token.new(tokenable: @plain_admin)).create?
  end

  test "a manager may not issue a card to the leader of a team above theirs" do
    assert_not TokenPolicy.new(@manager_user, Token.new(tokenable: @pack_leader)).create?
  end

  test "a manager may not issue a card that isn't held by a person" do
    assert_not TokenPolicy.new(@manager_user, Token.new).create?
  end

  test "a plain member may not issue a card, even to themselves" do
    assert_not TokenPolicy.new(@member_user, Token.new(tokenable: @member)).create?
  end

  test "a manager may change and delete the card of a member they manage" do
    policy = TokenPolicy.new(@manager_user, Token.create!(value: "1001", tokenable: @member))

    assert policy.update?
    assert policy.destroy?
  end

  test "a manager may not change or delete the card of an admin on their team" do
    policy = TokenPolicy.new(@manager_user, Token.create!(value: "1002", tokenable: @plain_admin))

    assert_not policy.update?
    assert_not policy.destroy?
  end

  test "a manager may not change or delete the card of the leader above them" do
    policy = TokenPolicy.new(@manager_user, Token.create!(value: "1003", tokenable: @pack_leader))

    assert_not policy.update?
    assert_not policy.destroy?
  end

  # --- scope --------------------------------------------------------------

  test "an admin sees every card" do
    assert_equal Token.count, TokenPolicy::Scope.new(@admin_user, Token).resolve.count
  end

  test "a manager sees only the cards they may change, plus their own" do
    own = Token.create!(value: "2001", tokenable: @manager)
    member = Token.create!(value: "2002", tokenable: @member)
    plain_admin = Token.create!(value: "2003", tokenable: @plain_admin)
    pack_leader = Token.create!(value: "2004", tokenable: @pack_leader)
    outsider = Token.create!(value: "2005", tokenable: @outsider)
    _, architect = create_person("architect", team: @den)
    architect.user.update!(architect: true)
    architect_card = Token.create!(value: "2006", tokenable: architect)

    scoped = TokenPolicy::Scope.new(@manager_user, Token).resolve

    assert_includes scoped, own
    assert_includes scoped, member
    assert_not_includes scoped, plain_admin
    assert_not_includes scoped, pack_leader
    assert_not_includes scoped, outsider
    assert_not_includes scoped, architect_card
  end

  test "a plain member sees only their own cards" do
    own = Token.create!(value: "3001", tokenable: @member)
    Token.create!(value: "3002", tokenable: @manager)

    assert_equal [ own ], TokenPolicy::Scope.new(@member_user, Token).resolve.to_a
  end

  private

  def create_person(name, team: nil, manager: false, admin: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin)
    person = Person.create!(user: user, first_name: name.capitalize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager) if team
    [ user, person ]
  end
end
