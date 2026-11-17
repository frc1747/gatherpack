require "test_helper"

class HookTest < ActiveSupport::TestCase
  test "catalog lists create, update and destroy for every hooked model" do
    hooked_tables = Dir[Rails.root.join("app/models/**/*.rb")]
      .select { |path| File.read(path).match?(/^\s*include CanBeHooked\b/) }
      .map { |path| path.delete_prefix("#{Rails.root.join("app/models")}/").delete_suffix(".rb").camelize.constantize.table_name }

    assert_includes hooked_tables, "time_clock_punches"

    catalog = Hook.catalog
    hooked_tables.each do |table|
      %w[ create update destroy ].each do |action|
        assert_includes catalog, "#{table} - #{action}"
      end
    end
  end

  test "catalog lists models that share a table once" do
    assert_equal 1, Hook.catalog.count("gateways - create")
  end

  test "catalog leaves out models that aren't hooked" do
    assert_not_includes Hook.catalog, "hooks - create"
  end

  test "catalog includes events and targets registered through GatherPack::HookCatalog" do
    targets = GatherPack::HookCatalog.targets.dup
    events = GatherPack::HookCatalog.events.dup
    GatherPack::HookCatalog.register_targets("things")
    GatherPack::HookCatalog.register_events("things - published")

    assert_includes Hook.catalog, "things - create"
    assert_includes Hook.catalog, "things - published"
    assert_equal 1, Hook.catalog.count("things - published")
  ensure
    GatherPack::HookCatalog.reset!
    GatherPack::HookCatalog.register_targets(targets)
    GatherPack::HookCatalog.register_events(events)
  end

  test "catalog keeps every event the hand-kept list used to offer" do
    tables = %w[ announcements badges badge_assignments events checkins memberships people relationships
                 relationship_types person_fields person_field_values person_field_badge_grants forms
                 form_responses form_submissions form_signatures form_badge_grants form_audience_rules
                 teams users pages tokens ledgers ledger_entries ledger_ownerships ledger_taggings
                 ledger_tags widgets ]
    previous = tables.product(%w[ create update destroy ]).map { |pair| pair.join(" - ") }

    assert_empty previous - Hook.catalog
  end

  test "catalog lists the domain events features register" do
    [ "person_fields - value changed", "form_submissions - submitted", "form_submissions - activated",
      "form_responses - completed", "form_responses - incomplete" ].each do |event|
      assert_includes Hook.catalog, event
    end
  end

  test "catalog no longer lists token - activate, which nothing fires" do
    assert_not_includes Hook.catalog, "token - activate"
  end

  test "an event registered twice is listed once" do
    Hook.register_event "widgets - render"
    Hook.register_event "widgets - render"

    assert_equal 1, Hook.catalog.count("widgets - render")
  ensure
    Hook.registered_events.delete("widgets - render")
  end

  test "catalog is sorted and unique" do
    catalog = Hook.catalog

    assert_equal catalog.uniq.sort, catalog
  end
end
