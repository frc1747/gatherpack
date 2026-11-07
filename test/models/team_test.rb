require "test_helper"

class TeamTest < ActiveSupport::TestCase
  def legacy_descendant_ids(team)
    team.children.flat_map { |child| [ child.id ] + legacy_descendant_ids(child) }
  end

  def build_team(name, parent = nil)
    Team.create!(name: name, team_type: team_types(:one), parent: parent)
  end

  def count_queries(&block)
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
    queries
  end

  test "subtree_ids includes the given teams and everything below them" do
    root = build_team("Root")
    child = build_team("Child", root)
    grandchild = build_team("Grandchild", child)
    other = build_team("Other")

    assert_equal [ root, child, grandchild ].map(&:id).sort, Team.subtree_ids(root.id).sort
    assert_equal [ child, grandchild ].map(&:id).sort, Team.subtree_ids([ child.id ]).sort
    assert_not_includes Team.subtree_ids(root.id), other.id
  end

  test "subtree_ids handles several roots without duplicates" do
    a = build_team("A")
    a1 = build_team("A1", a)
    b = build_team("B")
    b1 = build_team("B1", b)

    assert_equal [ a, a1, b, b1 ].map(&:id).sort, Team.subtree_ids([ a.id, b.id ]).sort
    # A root that is also below another root is returned once.
    assert_equal [ a, a1 ].map(&:id).sort, Team.subtree_ids([ a.id, a1.id ]).sort
  end

  test "subtree_ids returns nothing for no ids" do
    assert_equal [], Team.subtree_ids([])
    assert_equal [], Team.subtree_ids(nil)
  end

  test "subtree_ids walks a deep tree in one query" do
    teams = [ build_team("Level 0") ]
    30.times { |i| teams << build_team("Level #{i + 1}", teams.last) }

    ids = nil
    queries = count_queries { ids = Team.subtree_ids(teams.first.id) }

    assert_equal 1, queries.size
    assert_equal teams.map(&:id).sort, ids.sort
  end

  test "subtree_ids stops on a cycle" do
    a = build_team("A")
    b = build_team("B", a)
    a.update_columns(parent_id: b.id)

    assert_equal [ a, b ].map(&:id).sort, Team.subtree_ids(a.id).sort
  end

  test "all_descendant_ids matches the old recursion" do
    root = build_team("Root")
    left = build_team("Left", root)
    right = build_team("Right", root)
    build_team("Left leaf", left)
    deep = build_team("Right 1", right)
    build_team("Right 2", deep)

    Team.find_each do |team|
      assert_equal legacy_descendant_ids(team).sort, team.all_descendant_ids.sort, team.name
    end
    assert_not_includes root.all_descendant_ids, root.id
  end
end
