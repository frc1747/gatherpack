# Tests for bin/fork-merge-schema. Needs only git and the standard library,
# not the Rails app or its database:
#
#   ruby test/fork/fork_merge_schema_test.rb
require "minitest/autorun"
require "fileutils"
require "tmpdir"

load File.expand_path("../../bin/fork-merge-schema", __dir__)

class ForkMergeSchemaTest < Minitest::Test
  DRIVER = File.expand_path("../../bin/fork-merge-schema", __dir__)

  def setup
    @dir = Dir.mktmpdir("fork-merge-schema")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_newer_version_line_wins
    base = schema("2026_10_01_000000", tables: %w[a], keys: [])
    ours = schema("2026_10_02_000000", tables: %w[a b], keys: [])
    theirs = schema("2026_10_03_000000", tables: %w[a c], keys: [])

    merged, status = merge(base, ours, theirs)

    assert_equal 0, status
    assert_equal schema("2026_10_03_000000", tables: %w[a b c], keys: []), merged
  end

  def test_keeps_both_sides_tables_and_foreign_keys_that_sort_next_to_each_other
    base = schema("2026_10_01_000000", tables: %w[a z], keys: %w[a z])
    ours = schema("2026_10_02_000000", tables: %w[a forms mcp_calls z], keys: %w[a forms mcp_calls z])
    theirs = schema("2026_10_03_000000", tables: %w[a intake z], keys: %w[a intake z])

    merged, status = merge(base, ours, theirs)

    assert_equal 0, status
    assert_equal schema("2026_10_03_000000", tables: %w[a forms intake mcp_calls z], keys: %w[a forms intake mcp_calls z]), merged
  end

  def test_leaves_a_changed_existing_table_in_conflict
    base = schema("2026_10_01_000000", tables: %w[a], keys: [])
    ours = base.sub('t.string "name"', 't.string "title"')
    theirs = base.sub('t.string "name"', 't.text "name"')

    merged, status = merge(base, ours, theirs)

    assert_equal 1, status
    assert_match(/^<{7} ours$/, merged)
  end

  def test_leaves_part_of_a_block_in_conflict
    assert_nil ForkMergeSchema.resolve_hunk("    t.string \"x\"\n", "", "    t.string \"y\"\n")
  end

  def test_a_side_identical_to_the_other_is_kept_once
    statement = %(  add_foreign_key "a", "b"\n)
    assert_equal statement, ForkMergeSchema.resolve_hunk(statement, "", statement)
  end

  private

  def merge(base, ours, theirs)
    paths = { base: base, ours: ours, theirs: theirs }.to_h { |name, text| [ name, File.join(@dir, name.to_s).tap { |path| File.write(path, text) } ] }
    system(DRIVER, paths[:ours], paths[:base], paths[:theirs])
    [ File.read(paths[:ours]), $?.exitstatus ]
  end

  def schema(version, tables:, keys:)
    body = tables.map { |name| %(  create_table "#{name}", force: :cascade do |t|\n    t.string "name"\n  end\n) }.join("\n")
    body += "\n" + keys.map { |name| %(  add_foreign_key "#{name}", "people"\n) }.join unless keys.empty?
    "ActiveRecord::Schema[8.1].define(version: #{version}) do\n#{body}end\n"
  end
end
