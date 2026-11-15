require "test_helper"

# A merge must leave nothing pointing at the person (or login) it deletes.
# Every such column needs a registration in GatherPack::PersonMerge, or an
# exemption saying why it stays. New tables fail here until they get one.
class PersonMergeRegistryTest < ActiveSupport::TestCase
  test "every column pointing at a person is registered or exempt" do
    assert_empty uncovered(:person, "people", "person_id")
  end

  test "every column pointing at a login is registered or exempt" do
    assert_empty uncovered(:user, "users", "user_id")
  end

  test "every registered column exists" do
    missing = GatherPack::PersonMerge.entries.reject do |entry|
      connection.data_source_exists?(entry.table) && connection.column_exists?(entry.table, entry.column)
    end

    assert_empty missing.map { |e| "#{e.table}.#{e.column}" }
  end

  # Feature initializers that sort before person_merge.rb register first; a
  # reload of the built-ins must not wipe them.
  test "registrations made elsewhere survive the built-ins being prepared again" do
    GatherPack::PersonMerge.register(:checkin_field_responses, :checkin_id, label: "Probe")
    Rails.application.reloader.prepare!

    assert GatherPack::PersonMerge.covers?(:checkin_field_responses, :checkin_id)
    assert GatherPack::PersonMerge.covers?(:memberships, :person_id)
  ensure
    GatherPack::PersonMerge.unregister(:checkin_field_responses, :checkin_id)
  end

  private

  def connection
    ActiveRecord::Base.connection
  end

  # Columns named like the owner's key, foreign keys to its table, and
  # polymorphic id/type pairs (which can point at any model).
  def uncovered(owner, owner_table, owner_column)
    connection.tables.flat_map do |table|
      names = connection.columns(table).map(&:name)
      columns = names.select { |name| name == owner_column }
      columns += connection.foreign_keys(table).select { |fk| fk.to_table == owner_table }.map(&:column)
      columns += names.select { |name| name.end_with?("_id") && names.include?(name.delete_suffix("_id") + "_type") }
      columns.uniq.reject { |column| GatherPack::PersonMerge.covers?(table, column, owner: owner) }.map { |column| "#{table}.#{column}" }
    end
  end
end
