require "test_helper"

class TableResponsiveTest < ActiveSupport::TestCase
  # Templates that are not screens (emails, PDFs, print-only) may use bare tables.
  EXEMPT = %r{\A(app/views/[^/]*_mailer/|app/views/layouts/mailer|.*\.text\.erb\z|.*\.pdf\.erb\z|.*print)}

  test "every table in a screen template is wrapped in table-responsive" do
    unwrapped = Dir.glob("app/views/**/*.erb").sort.flat_map do |path|
      next [] if path.match?(EXEMPT)

      lines = File.readlines(path)
      lines.each_index.select { |i| lines[i].match?(/<table\b/) }.reject do |i|
        lines[i].include?("table-responsive") || lines[0...i].reverse.find { |l| l.strip.present? }&.include?("table-responsive")
      end.map { |i| "#{path}:#{i + 1}" }
    end

    assert_empty unwrapped, "Wrap these tables in <div class=\"table-responsive\">"
  end
end
