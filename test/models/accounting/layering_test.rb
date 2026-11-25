require "test_helper"

# Sources and rules are separate layers: only a source's own code knows its
# system's field names, and the rest of the feature reads the neutral
# columns, never the raw data.
class Accounting::LayeringTest < ActiveSupport::TestCase
  QUICKBOOKS_FIELDS = %w[ TotalAmt LinkedTxn UnappliedAmt ItemRef CustomerRef ].freeze
  QUICKBOOKS_FILES = [ "app/models/accounting/quickbooks/", "app/models/gateway/quickbooks_gateway.rb" ].freeze

  # The code that copies records stores and hands on the raw data; nothing
  # else outside the sources' own folders reads it.
  DATA_READERS = [
    "app/models/accounting/quickbooks/", "app/models/gateway/quickbooks_gateway.rb",
    "app/models/accounting/ledgers/", "app/models/gateway/ledger_source.rb",
    "app/models/accounting/files/", "app/models/gateway/file_source.rb",
    "app/models/accounting/sync.rb"
  ].freeze

  test "QuickBooks field names appear only in the QuickBooks source" do
    offending = ruby_and_view_files.reject { |file| QUICKBOOKS_FILES.any? { |allowed| file.start_with?(allowed) } }.select do |file|
      QUICKBOOKS_FIELDS.any? { |field| File.read(Rails.root.join(file)).include?(field) }
    end

    assert_empty offending
  end

  test "accounting code outside the sources never reads a record's raw data" do
    files = ruby_and_view_files.select { |file| file.start_with?("app/models/accounting/", "app/jobs/accounting/", "app/controllers/accounting/") }
    offending = files.reject { |file| DATA_READERS.any? { |allowed| file.start_with?(allowed) } }.select do |file|
      File.read(Rails.root.join(file)).match?(/\.data\b|\[:data\]|\["data"\]/)
    end

    assert_empty offending
  end

  private
    def ruby_and_view_files
      Dir.chdir(Rails.root) { Dir["{app,lib}/**/*.{rb,erb}"] }
    end
end
