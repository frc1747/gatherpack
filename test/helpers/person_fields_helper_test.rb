require "test_helper"
require_relative "../support/person_fields_world"
require_relative "../support/settings_test_helper"

class PersonFieldsHelperTest < ActionView::TestCase
  include ApplicationHelper
  include PersonFieldsWorld
  include SettingsTestHelper

  setup do
    build_person_fields_world
  end

  test "audience_for reports each role's access for every level" do
    expected = {
      "admin" => { subject: :none, guardians: :none, leaders: :none, teammates: :none, everyone: :none },
      "self" => { subject: :read, guardians: :none, leaders: :none, teammates: :none, everyone: :none },
      "leaders" => { subject: :none, guardians: :none, leaders: :read, teammates: :none, everyone: :none },
      "self_and_leaders" => { subject: :read, guardians: :none, leaders: :read, teammates: :none, everyone: :none },
      "guardians" => { subject: :none, guardians: :read, leaders: :read, teammates: :none, everyone: :none },
      "family" => { subject: :read, guardians: :read, leaders: :read, teammates: :none, everyone: :none },
      "team" => { subject: :read, guardians: :read, leaders: :read, teammates: :read, everyone: :none },
      "everyone" => { subject: :read, guardians: :read, leaders: :read, teammates: :read, everyone: :read }
    }

    expected.each do |level, roles|
      field = create_world_field("Field #{level}", read: level)
      assert_equal roles, field.audience_for(person(:a1)).slice(*roles.keys), level
    end

    field = create_world_field("Written", read: "family", write: "self_and_leaders")
    audience = field.audience_for(person(:a1))
    assert_equal({ subject: :write, guardians: :read, leaders: :write }, audience.slice(:subject, :guardians, :leaders))
  end

  test "audience_for lists badge grants and leaves out guardians the person doesn't have" do
    field = create_world_field("Medical", read: "family")
    field.person_field_badge_grants.create!(badge: @health_officer_badge, access: :write)
    assert_equal({ @health_officer_badge => :write }, field.audience_for(person(:a1))[:badges])
    assert field.audience_for(person(:a1)).key?(:guardians)

    assert_not field.audience_for(person(:parent_a1)).key?(:guardians)
    assert_not field.audience_for(person(:den_a_leader)).key?(:guardians)
  end

  test "people without guardians see no notes about guardians" do
    shared = create_world_field("Shared", read: "family", write: "family")
    private_field = create_world_field("Private", read: "leaders")

    assert_empty access_notes(shared, person(:parent_a1), person(:parent_a1))
    assert_empty access_notes(shared, person(:den_a_leader), person(:den_a_leader))
    assert_equal [ "DenALeader World can't see this." ], access_notes(private_field, person(:den_a_leader), person(:pack_leader))
    assert_equal [ "Visible to: ParentA1 World, ParentA1 World's leaders." ], access_notes(shared, person(:parent_a1), person(:admin))
  end

  test "audience_for reports when a minor guardianship ends" do
    person(:a1).update!(birthday: 17.years.ago.to_date + 30.days)
    field = create_world_field("Medical", read: "family")

    with_settings(guardianship_age_limit: "18") do
      assert_equal person(:a1).birthday + 18.years, field.audience_for(person(:a1))[:guardianship_ends_on]
    end
  end

  test "notes for a guardian say what the child can see" do
    {
      [ "guardians", "leaders" ] => "Not visible to A1 World.",
      [ "family", "leaders" ] => "A1 World can see this but can't change it.",
      [ "family", "family" ] => "A1 World can see and change this."
    }.each do |(read, write), note|
      field = create_world_field("#{read} #{write}", read: read, write: write)
      assert_equal [ note ], access_notes(field, person(:a1), person(:parent_a1))
    end
  end

  test "a guardian is warned when their access is about to end" do
    person(:a1).update!(birthday: 18.years.ago.to_date + 30.days)
    field = create_world_field("Medical", read: "family", write: "family")

    with_settings(guardianship_age_limit: "18") do
      notes = access_notes(field, person(:a1), person(:parent_a1))
      assert_includes notes, "Your access to A1 World's restricted fields ends on #{nice_date(Date.current + 30.days)}."
    end
  end

  test "notes for the person themself" do
    shared = create_world_field("Shared", read: "family", write: "family")
    leaders_write = create_world_field("Leaders write", read: "family", write: "leaders")

    assert_equal [ "Your guardians can see and change this." ], access_notes(shared, person(:a1), person(:a1))
    assert_equal [ "Your guardians can see this.", "Only your leaders can change this." ], access_notes(leaders_write, person(:a1), person(:a1))
  end

  test "notes for a leader" do
    private_field = create_world_field("Private", read: "leaders")
    guardians_field = create_world_field("Concerns", read: "guardians")

    assert_equal [ "A1 World's guardians can't see this.", "A1 World can't see this." ], access_notes(private_field, person(:a1), person(:den_a_leader))
    assert_equal [ "A1 World can't see this." ], access_notes(guardians_field, person(:a1), person(:den_a_leader))
  end

  test "badge grants are mentioned to everyone, and admins get the summary" do
    field = create_world_field("Medical", read: "family")
    field.person_field_badge_grants.create!(badge: @health_officer_badge, access: :read)

    assert_includes access_notes(field, person(:a1), person(:parent_a1)), "Also visible to Health Officer badge holders."
    assert_equal [ "Visible to: A1 World, A1 World's guardians, A1 World's leaders, Health Officer." ], access_notes(field, person(:a1), person(:admin))
  end

  test "fields visible to everyone get no notes" do
    field = create_world_field("Nickname", read: "everyone", write: "self_and_leaders")

    assert_empty access_notes(field, person(:a1), person(:a1))
    assert_empty access_notes(field, person(:a1), person(:a2))
  end

  test "the guardians level is only offered once guardianship is configured" do
    assert_includes person_field_level_options.map(&:last), "guardians"
    assert_includes person_field_level_description("family"), "Parent of"

    RelationshipType.update_all(guardianship: RelationshipType.guardianships[:none])
    assert_not_includes person_field_level_options.map(&:last), "guardians"
    assert_includes person_field_level_options, [ "This person and their leaders", "family" ]
    assert_not_includes person_field_level_description("family"), "guardian"
  end
end
