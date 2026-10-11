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

  test "catalog lists token - activate" do
    assert_includes Hook.catalog, "token - activate"
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
