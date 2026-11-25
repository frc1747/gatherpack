require "test_helper"
require_relative "../../support/accounting_rules_world"

class Accounting::RulePermissionsTest < ActiveSupport::TestCase
  include AccountingRulesWorld

  setup do
    @team = create_rule_team("Robotics")
    @nancy = create_rule_person("Nancy", "Davolio", team: @team, customer: "58")
    @laura = create_rule_person("Laura", "Callahan", admin: true)
    @margaret = create_rule_person("Margaret", "Peacock")
    add_guardian(@margaret, @nancy, by: @laura)
    @andrew = create_rule_person("Andrew", "Fuller", team: @team, manager: true)
    @janet = create_rule_person("Janet", "Leverling", team: @team)
    @steven = create_rule_person("Steven", "Buchanan")
    @viewers = { subject: @nancy, guardian: @margaret, leader: @andrew, teammate: @janet, stranger: @steven }
    add_charge("58", "I1", total: 40_000, balance: 10_000)
  end

  READERS = {
    "admin" => [],
    "self" => %i[ subject ],
    "leaders" => %i[ leader ],
    "self_and_leaders" => %i[ subject leader ],
    "guardians" => %i[ guardian leader ],
    "family" => %i[ subject guardian leader ],
    "team" => %i[ subject guardian leader teammate ],
    "everyone" => %i[ subject guardian leader teammate stranger ]
  }.freeze

  test "results at each level reach the subject, guardian, leader, teammate and stranger the level names" do
    READERS.each do |level, expected|
      rule = create_rule("Dues #{level}", read_permission: level, amount_permission: "admin")
      evaluate(rule)

      readers = @viewers.select { |_, viewer| access(viewer, rule).can_read? }.keys
      assert_equal expected, readers, "read_permission #{level}"
      @viewers.each do |role, viewer|
        assert_equal readers.include?(role), rule.readable_people_for(viewer).include?(@nancy), "#{level}: relation and check agree for #{role}"
        assert_not access(viewer, rule).can_see_amounts?, "#{level}: amounts stay admin-only for #{role}"
      end
      assert access(@laura, rule).can_see_amounts?
      assert rule.readable_people_for(@laura).include?(@nancy)
    end
  end

  test "amounts at each level reach only people who also see the result" do
    { "self" => %i[ subject ], "guardians" => %i[ guardian leader ], "family" => %i[ subject guardian leader ], "team" => %i[ subject guardian leader teammate ] }.each do |level, expected|
      rule = create_rule("Dues #{level}", read_permission: "team", amount_permission: level)

      seers = @viewers.select { |_, viewer| access(viewer, rule).can_see_amounts? }.keys
      assert_equal expected, seers, "amount_permission #{level}"
      @viewers.each do |role, viewer|
        assert_equal seers.include?(role), rule.amount_people_for(viewer).include?(@nancy), "#{level}: relation and check agree for #{role}"
      end
    end
  end

  test "amount_permission must sit within read_permission" do
    rule = AccountingRule.new(name: "Dues", kind: "balance", gateway: accounting_source, read_permission: "self", amount_permission: "family")

    assert_not rule.valid?
    assert_includes rule.errors[:amount_permission], "can't include people who can't see the result"
    rule.read_permission = "team"
    assert rule.valid?
  end

  test "a badge grant shows results, and amounts with amounts" do
    robert = create_rule_person("Robert", "King")
    treasurer = create_rule_badge("Treasurer")
    BadgeAssignment.create!(badge: treasurer, person: robert)
    rule = create_rule(read_permission: "admin", amount_permission: "admin")
    evaluate(rule)

    with_settings(feature_badges: "true") do
      assert_not access(robert, rule).can_read?

      grant = rule.badge_grants.create!(badge: treasurer)
      rule.reload
      assert access(robert, rule).can_read?
      assert_not access(robert, rule).can_see_amounts?
      assert rule.readable_people_for(robert).include?(@nancy)
      assert_not rule.amount_people_for(robert).include?(@nancy)

      grant.update!(amounts: true)
      rule.reload
      assert access(robert, rule).can_see_amounts?
      assert rule.amount_people_for(robert).include?(@nancy)
      assert_not access(@steven, rule).can_read?
    end

    with_settings(feature_badges: "false") { assert_not access(robert, rule.reload).can_read? }
  end

  test "393#2: any grant the viewer holds that shows amounts shows them, whatever order the grants come in" do
    robert = create_rule_person("Robert", "King")
    mentor = create_rule_badge("Mentor")
    treasurer = create_rule_badge("Treasurer")
    [ mentor, treasurer ].each { |badge| BadgeAssignment.create!(badge: badge, person: robert) }
    rule = create_rule(read_permission: "admin", amount_permission: "admin")
    rule.badge_grants.create!(badge: mentor, amounts: false)
    rule.badge_grants.create!(badge: treasurer, amounts: true)
    evaluate(rule)

    with_settings(feature_badges: "true") do
      rule.reload
      assert access(robert, rule).can_read?
      assert access(robert, rule).can_see_amounts?
      assert rule.amount_people_for(robert).include?(@nancy)
      assert_equal [ treasurer.id ], rule.grants_held_by(robert, amounts: true).map(&:badge_id)
    end
  end

  test "a team badge grant covers only that team and below; only admin-assigned badges can grant" do
    robert = create_rule_person("Robert", "King")
    other = create_rule_team("Drama")
    badge = create_rule_badge("Drama treasurer", team: other)
    Membership.create!(person: robert, team: other)
    BadgeAssignment.create!(badge: badge, person: robert)
    rule = create_rule
    rule.badge_grants.create!(badge: badge, amounts: true)

    with_settings(feature_badges: "true") { assert_not access(robert, rule.reload).can_read? }

    self_assigned = create_rule_badge("Volunteer", team: other, permission: :added_by_manager)
    assert_not rule.badge_grants.build(badge: self_assigned).valid?
  end

  test "the Account tab shows only when the viewer sees one of the person's results" do
    rule = create_rule(read_permission: "family", amount_permission: "family")
    evaluate(rule)

    assert Accounting::Access.sees_any_result?(@nancy.user, @nancy)
    assert Accounting::Access.sees_any_result?(@margaret.user, @nancy)
    assert_not Accounting::Access.sees_any_result?(@janet.user, @nancy)
    assert_not Accounting::Access.sees_any_result?(@steven.user, @nancy)

    rule.update!(enabled: false)
    assert_not Accounting::Access.sees_any_result?(@nancy.user, @nancy)
    assert Accounting::Access.sees_any_result?(@laura.user, @nancy)
  end

  test "the list shows the rules whose results the viewer sees" do
    family = create_rule("Dues", read_permission: "family")
    admin_only = create_rule("Given")
    evaluate(family)
    evaluate(admin_only)

    assert_equal [ family ], Accounting::Access.visible_rules(@margaret.user)
    assert_equal [], Accounting::Access.visible_rules(@steven.user)
    assert_not Accounting::Access.sees_any_rule?(@steven.user)
    assert_equal [ family, admin_only ].sort_by(&:name), Accounting::Access.visible_rules(@laura.user).to_a.sort_by(&:name)
  end

  test "counts cover the people the viewer sees; totals only those whose amounts they may see" do
    rule = create_rule(read_permission: "team", amount_permission: "self", team: @team)
    evaluate(rule)

    mine = Accounting::RuleSummary.new(rule, @nancy)
    assert_equal [ [ "not_invoiced", "Not invoiced", 2 ], [ "partial", "Partly paid", 1 ] ], mine.counts
    assert_equal [ 1, 3 ], [ mine.amount_people_count, mine.people_count ]
    assert_equal({ charged: 40_000, paid: 30_000, balance: 10_000 }, mine.totals)

    theirs = Accounting::RuleSummary.new(rule, @margaret)
    assert_not theirs.amounts?
    assert_equal 1, theirs.people_count
  end

  private
    def access(viewer, rule)
      Accounting::RuleAccess.new(viewer, @nancy, rule)
    end
end
