require "test_helper"
require_relative "../support/checklists_world"
require_relative "../support/checklists_test_kinds"

# A person's row shows when the overall or any item reaches the viewer, and
# the overall only at its own level. The checklist list follows the same
# reach, including an item's group or team level.
class ChecklistRowReachTest < ActiveSupport::TestCase
  include ChecklistsWorld

  setup do
    Checklists.register_item_kind(:pooled, ChecklistsTestKinds::Pooled)
    build_checklists_world
    @checklist = create_world_checklist
    add_rule(@checklist, :include, :team, team_id: @members.id)
    @login = add_item(@checklist, :has_login, "Login")
    @pooled = add_item(@checklist, :pooled, "Shifts")
    # A relative who isn't a guardian and on no team.
    @dad = Person.create!(first_name: "Dad", last_name: "World", user: User.create!(email: "dad@example.com", password: "Password1!"))
    uncle_of = RelationshipType.create!(parent_label: "Relative of", child_label: "Relative of", permission: :added_by_admin, guardianship: :none)
    Relationship.create!(parent: @dad, child: person(:member), relationship_type: uncle_of, created_by: person(:admin))
    refresh(@checklist)
  end

  teardown do
    Checklists.unregister_item_kind(:pooled)
  end

  test "a pooled relative who isn't a guardian sees the pooled item, without the overall" do
    statuses = Checklists.status_for(@checklist, [ person(:member), person(:member2) ], viewer: @dad)

    assert_equal [ person(:member).id ], statuses.keys
    status = statuses[person(:member).id]
    assert_nil status.overall, "the overall's level (family) doesn't reach him"
    assert_equal [ @pooled.id ], status.items.map { |entry| entry.item.id }
    assert_equal "1 of 2 shifts", status.items.first.summary
    assert Checklists::Visibility.new(@checklist, @dad).row_visible?(person(:member).id, [ @pooled ])
    assert_not Checklists::Visibility.new(@checklist, @dad).row_visible?(person(:member).id)
  end

  test "the checklist list reaches him through the item's group level" do
    assert ChecklistPolicy.new(@dad.user, @checklist).show?
    assert_includes ChecklistPolicy::Scope.new(@dad.user, Checklist).resolve, @checklist
    assert_equal [ @checklist ], Checklists.checklist_for(person(:member), viewer: @dad).map(&:first)

    stranger = Person.create!(first_name: "Nobody", last_name: "World", user: User.create!(email: "nobody@example.com", password: "Password1!"))
    assert_not ChecklistPolicy.new(stranger.user, @checklist).show?
  end

  test "a teammate reaches an item open to the team, but not the overall" do
    @login.update!(read_level: "team")
    refresh(@checklist)
    outsider_teammate = Person.create!(first_name: "Mate", last_name: "World", user: User.create!(email: "mate@example.com", password: "Password1!"))
    Membership.create!(person: outsider_teammate, team: @members)
    other = create_world_checklist("Elsewhere", team: @crew)
    add_item(other, :has_login, "Login", {}, read_level: "team")
    refresh(other)

    status = Checklists.status_for(@checklist, [ person(:member2) ], viewer: outsider_teammate)[person(:member2).id]
    assert_nil status.overall
    assert_equal [ @login.id ], status.items.map { |entry| entry.item.id }
    assert_includes ChecklistPolicy::Scope.new(outsider_teammate.user, Checklist).resolve, @checklist
    assert_not_includes ChecklistPolicy::Scope.new(outsider_teammate.user, Checklist).resolve, other, "no teammate there"
  end

  test "the report and person page render rows without an overall" do
    report = Checklists::Report.new(@checklist, @dad)

    assert_equal [ person(:member).id ], report.statuses.keys
    assert_equal({}, report.counts)
    assert_equal [ [ nil, report.statuses.values ] ], report.sections
  end
end
