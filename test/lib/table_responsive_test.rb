require "test_helper"

class TableResponsiveTest < ActiveSupport::TestCase
  TEMPLATES = %w[
    app/views/audit_logs/show.html.erb
    app/views/relationship_types/show.html.erb
    app/views/theme/edit.html.erb
  ].freeze

  test "tables in wide screen templates are wrapped in table-responsive" do
    TEMPLATES.each do |path|
      lines = File.readlines(path)
      tables = lines.each_index.select { |i| lines[i].match?(/<table\b/) }

      assert_not_empty tables, "#{path} has no table"
      tables.each do |i|
        previous = lines[0...i].reverse.find { |l| l.strip.present? }
        assert_includes previous, "table-responsive", "#{path}:#{i + 1} table is not wrapped"
      end
    end
  end
end
