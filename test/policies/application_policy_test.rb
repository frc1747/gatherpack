require "test_helper"

class ApplicationPolicyTest < ActiveSupport::TestCase
  setup do
    # Pack
    # ├── Den A (run by @den_leader)
    # │   └── Patrol
    # └── Den B
    # Other Org (unrelated)
    @pack = Team.create!(name: "Pack", team_type: team_types(:one))
    @den_a = Team.create!(name: "Den A", team_type: team_types(:one), parent: @pack)
    @patrol = Team.create!(name: "Patrol", team_type: team_types(:one), parent: @den_a)
    @den_b = Team.create!(name: "Den B", team_type: team_types(:one), parent: @pack)
    @other_org = Team.create!(name: "Other Org", team_type: team_types(:one))

    @den_leader_user = User.create!(email: "den-leader@example.com", password: "Password1!")
    @den_leader = Person.create!(user: @den_leader_user, first_name: "Dana", last_name: "Leader")
    Membership.create!(person: @den_leader, team: @den_a, manager: true)
  end

  # --- teams --------------------------------------------------------------

  test "a manager manages their own team" do
    assert manages?(@den_leader_user, @den_a)
  end

  test "a manager manages a descendant of their team" do
    assert manages?(@den_leader_user, @patrol)
  end

  test "a manager does not manage an ancestor of their team" do
    assert_not manages?(@den_leader_user, @pack)
  end

  test "a manager does not manage a sibling of their team" do
    assert_not manages?(@den_leader_user, @den_b)
  end

  test "a manager does not manage an unrelated team" do
    assert_not manages?(@den_leader_user, @other_org)
  end

  test "a plain member does not manage their team" do
    member_user, = create_person("member", team: @den_a)
    assert_not manages?(member_user, @den_a)
  end

  # --- people -------------------------------------------------------------

  test "a manager manages a member of their team" do
    _, member = create_person("member", team: @den_a)
    assert manages?(@den_leader_user, member)
  end

  test "a manager manages a member of a descendant team" do
    _, member = create_person("patrol-member", team: @patrol)
    assert manages?(@den_leader_user, member)
  end

  test "a manager does not manage an admin who is a member of their team" do
    _, admin = create_person("admin", team: @den_a, admin: true)
    assert_not manages?(@den_leader_user, admin)
  end

  test "a manager does not manage an architect who is a member of their team" do
    _, architect = create_person("architect", team: @den_a, architect: true)
    assert_not manages?(@den_leader_user, architect)
  end

  test "a manager does not manage the manager of their parent team" do
    _, pack_leader = create_person("pack-leader", team: @pack, manager: true)
    assert_not manages?(@den_leader_user, pack_leader)
  end

  test "a manager does not manage the parent team's manager even when they're a member of the team" do
    _, pack_leader = create_person("pack-leader", team: @pack, manager: true)
    Membership.create!(person: pack_leader, team: @den_a, manager: false)
    assert_not manages?(@den_leader_user, pack_leader)
  end

  test "the manager of a parent team manages the manager of a sub-team" do
    pack_leader_user, = create_person("pack-leader", team: @pack, manager: true)
    assert manages?(pack_leader_user, @den_leader)
  end

  test "co-managers of a team manage each other" do
    co_leader_user, co_leader = create_person("co-leader", team: @den_a, manager: true)
    assert manages?(@den_leader_user, co_leader)
    assert manages?(co_leader_user, @den_leader)
  end

  test "a manager manages the manager of a descendant team" do
    _, patrol_leader = create_person("patrol-leader", team: @patrol, manager: true)
    assert manages?(@den_leader_user, patrol_leader)
  end

  test "a manager does not manage a member of a sibling or unrelated team" do
    _, den_b_member = create_person("den-b-member", team: @den_b)
    _, outsider = create_person("outsider", team: @other_org)
    assert_not manages?(@den_leader_user, den_b_member)
    assert_not manages?(@den_leader_user, outsider)
  end

  test "a manager does not manage someone with no team" do
    _, loner = create_person("loner")
    assert_not manages?(@den_leader_user, loner)
  end

  # --- other records ------------------------------------------------------

  test "a manager manages a record that belongs to a team they manage" do
    assert manages?(@den_leader_user, Event.new(team: @patrol))
    assert_not manages?(@den_leader_user, Event.new(team: @pack))
  end

  test "a record without a team is not managed" do
    assert_not manages?(@den_leader_user, Event.new)
    assert_not manages?(@den_leader_user, nil)
  end

  # --- no person ----------------------------------------------------------

  test "a user without a person manages nothing" do
    user = User.create!(email: "no-person@example.com", password: "Password1!")
    _, member = create_person("member", team: @den_a)
    assert_not manages?(user, @den_a)
    assert_not manages?(user, member)
  end

  # --- default deny -------------------------------------------------------

  ACTIONS = %i[ index? show? new? create? edit? update? destroy? ].freeze

  test "the base policy refuses every action, even to an admin" do
    admin_user, = create_person("admin", admin: true, architect: true)
    member_user, = create_person("member", team: @den_a)

    [ admin_user, member_user, @den_leader_user ].each do |user|
      ACTIONS.each do |action|
        assert_not ApplicationPolicy.new(user, @den_a).public_send(action), "#{action} for #{user.email}"
      end
    end
  end

  test "a policy that defines no actions refuses them all" do
    policy_class = Class.new(ApplicationPolicy)
    admin_user, = create_person("admin", admin: true, architect: true)

    ACTIONS.each do |action|
      assert_not policy_class.new(admin_user, @den_a).public_send(action), action
      assert_not policy_class.new(@den_leader_user, @den_a).public_send(action), action
    end
  end

  # Since the base refuses everything, a policy has to define each action its
  # controller routes to. new? and edit? follow create? and update?.
  test "every routed action is defined on its policy" do
    missing = []
    assert_operator routed_policy_actions.size, :>, 100, "expected most routes to be checked"

    routed_policy_actions.each do |policy_class, action|
      owner = policy_class.instance_method(action).owner
      missing << "#{policy_class.name}##{action}" if owner == ApplicationPolicy
    end

    assert_empty missing
  end

  # Nested controllers that authorize the parent record with the child's
  # action name, so the parent's policy needs a method for each child route.
  PARENT_AUTHORIZATIONS = {
    "LedgerEntriesController" => LedgerPolicy,      # set_ledger
    "MailboxMessagesController" => MailboxPolicy,   # set_mailbox
    "RepliesController" => QuestionPolicy,          # set_question
    "ReplyVotesController" => QuestionPolicy        # set_question
  }.freeze

  # Known gaps, older than default deny: unvote has no QuestionPolicy#unvote?,
  # so it raises NoMethodError for everyone.
  KNOWN_PARENT_GAPS = %w[ QuestionPolicy#unvote? ].freeze

  test "every routed child action is defined on the parent's policy" do
    missing = []
    assert_operator routed_parent_actions.size, :>, 10, "expected the nested routes to be checked"

    routed_parent_actions.each do |policy_class, action|
      name = "#{policy_class.name}##{action}"
      next if KNOWN_PARENT_GAPS.include?(name)

      missing << name unless policy_class.method_defined?(action) && defined_on_policy?(policy_class, action)
    end

    assert_empty missing
  end

  # --- not a policy action ------------------------------------------------

  test "manages? can't be called as a policy action" do
    assert_not ApplicationPolicy.new(@den_leader_user, @den_a).respond_to?(:manages?)
  end

  private

  POLICY_ACTIONS = { "show" => :show?, "new" => :create?, "create" => :create?, "edit" => :update?, "update" => :update?, "destroy" => :destroy? }.freeze

  # [policy class, action] for each RESTful route whose controller is named
  # after its model. Other actions authorize with explicit policy methods.
  def routed_policy_actions
    Rails.application.routes.routes.filter_map do |route|
      action = POLICY_ACTIONS[route.defaults[:action]] or next
      controller = "#{route.defaults[:controller]&.camelize}Controller".safe_constantize
      next unless controller && controller < ApplicationController

      model = controller.controller_name.classify.safe_constantize
      model = LedgerOwnership if controller == LedgerOwnershipsController
      policy_class = model && Pundit::PolicyFinder.new(model).policy
      [ policy_class, action ] if policy_class
    end.uniq
  end

  # [parent policy class, action?] for each route of a controller in
  # PARENT_AUTHORIZATIONS; Pundit asks the parent "#{action_name}?".
  def routed_parent_actions
    Rails.application.routes.routes.filter_map do |route|
      policy_class = PARENT_AUTHORIZATIONS["#{route.defaults[:controller]&.camelize}Controller"] or next
      [ policy_class, :"#{route.defaults[:action]}?" ]
    end.uniq
  end

  # new? and edit? count when the policy defines what they follow.
  def defined_on_policy?(policy_class, action)
    action = { new?: :create?, edit?: :update? }.fetch(action, action) if policy_class.instance_method(action).owner == ApplicationPolicy
    policy_class.instance_method(action).owner != ApplicationPolicy
  end

  def manages?(user, record)
    ApplicationPolicy.new(user, record).send(:manages?, record)
  end

  def create_person(name, team: nil, manager: false, admin: false, architect: false)
    user = User.create!(email: "#{name}@example.com", password: "Password1!", admin: admin, architect: architect)
    person = Person.create!(user: user, first_name: name.titleize, last_name: "Test")
    Membership.create!(person: person, team: team, manager: manager) if team
    [ user, person ]
  end
end
