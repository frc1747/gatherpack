require "test_helper"

class TableFilterParamsTest < ActiveSupport::TestCase
  Row = Struct.new(:name, :team, :amount, :due)

  ROWS = [
    Row.new("Ben", "Build", "$1,200", "2026-03-01"),
    Row.new("ana", "Code", "$90", "2025-12-24"),
    Row.new("Cleo", "Build", "$5", ""),
    Row.new("Dev", "", "", "2026-01-15")
  ].freeze

  COLUMNS = {
    "Name" => ->(row) { row.name },
    "Team" => ->(row) { row.team },
    "amount" => ->(row) { row.amount },
    "Due" => ->(row) { row.due }
  }.freeze

  def names(filters = nil, **options)
    TableFilterParams.new(filters, **options).apply(ROWS, COLUMNS).map(&:name)
  end

  test "with nothing carried, every row in its own order" do
    assert_equal %w[Ben ana Cleo Dev], names
    assert_not TableFilterParams.new(nil).active?
  end

  test "one chosen value keeps the rows whose cell is exactly it" do
    assert_equal %w[Ben Cleo], names({ "Team" => "Build" })
    assert_equal [], names({ "Team" => "build" })
    assert_equal [], names({ "Team" => "Buil" })
  end

  test "several chosen values keep rows with any of them, and blank is a value" do
    assert_equal %w[Ben Cleo Dev], names({ "Team" => [ "Build", "" ] })
  end

  test "filters on several columns combine" do
    assert_equal %w[Cleo], names({ "Team" => [ "Build" ], "amount" => [ "$5", "$90" ] })
  end

  test "cell text is compared with its whitespace collapsed and trimmed" do
    rows = [ Row.new("Eli", "  Build\n  team ") ]
    assert_equal rows, TableFilterParams.new({ "Team" => " Build  team" }).apply(rows, COLUMNS)
  end

  test "unknown keys are ignored, for filters and for the sort" do
    assert_equal %w[Ben ana Cleo Dev], names({ "Shirt size" => "M" }, sort: "Shirt size", dir: "desc")
    assert_equal %w[Ben Cleo], names({ "Team" => "Build", "Shirt size" => "M" })
  end

  test "text sorts in natural order without case, blanks last; desc reverses with blanks first" do
    assert_equal %w[ana Ben Cleo Dev], names(sort: "Name")
    assert_equal %w[Dev Cleo Ben ana], names(sort: "Name", dir: "desc")
    assert_equal %w[Ben Cleo ana Dev], names(sort: "Team")
    assert_equal %w[Dev ana Ben Cleo], names(sort: "Team", dir: "desc")
  end

  test "numbers compare as numbers ignoring $ and commas" do
    assert_equal %w[Cleo ana Ben Dev], names(sort: "amount")
    assert_equal %w[Dev Ben ana Cleo], names(sort: "amount", dir: "desc")
  end

  test "dates compare as dates" do
    assert_equal %w[ana Dev Ben Cleo], names(sort: "Due")
    assert_equal %w[Cleo Ben Dev ana], names(sort: "Due", dir: "desc")
  end

  test "digit runs in text compare by size, and numbers come before text" do
    rows = %w[Item10 item2 Item1 7 Älpha alpha].map { |name| Row.new(name) }
    sorted = TableFilterParams.new(nil, sort: "Name").apply(rows, COLUMNS).map(&:name)
    assert_equal %w[7 Älpha alpha Item1 item2 Item10], sorted
  end

  test "text in other scripts sorts by its alphabet, not dropped to placeholders" do
    rows = %w[Вера Борис анна Ёлка Zoe].map { |name| Row.new(name) }
    sorted = TableFilterParams.new(nil, sort: "Name").apply(rows, COLUMNS).map(&:name)
    assert_equal %w[Zoe анна Борис Вера Ёлка], sorted
  end

  test "a filter param that isn't a set of keys counts as no filters" do
    [ "x", [ "x" ], ActionController::Parameters.new(tf: "x")[:tf], ActionController::Parameters.new(tf: [ "x" ])[:tf] ].each do |filters|
      carried = TableFilterParams.new(filters, sort: "Name")
      assert_equal({}, carried.filters)
      assert_equal %w[ana Ben Cleo Dev], carried.apply(ROWS, COLUMNS).map(&:name)
    end
  end

  test "a sort param that isn't a single key is ignored" do
    assert_equal %w[Ben ana Cleo Dev], names(sort: [ "Name" ])
    assert_equal %w[Ben ana Cleo Dev], names(sort: { "Name" => "x" })
  end

  test "the sort is stable for equal values in both directions" do
    rows = [ Row.new("A", "x"), Row.new("B", "X"), Row.new("C", "x") ]
    assert_equal %w[A B C], TableFilterParams.new(nil, sort: "Team").apply(rows, COLUMNS).map(&:name)
    assert_equal %w[A B C], TableFilterParams.new(nil, sort: "Team", dir: "desc").apply(rows, COLUMNS).map(&:name)
  end

  test "reads request parameters as the carry sends them" do
    params = ActionController::Parameters.new(tf: { "Team" => [ "Build" ], "amount" => "$5" }, tf_sort: "Name", tf_dir: "desc")
    carried = TableFilterParams.new(params[:tf], sort: params[:tf_sort], dir: params[:tf_dir])

    assert carried.active?
    assert_equal %w[Cleo], carried.apply(ROWS, COLUMNS).map(&:name)
    assert_equal %w[Cleo Ben], TableFilterParams.new({ "Team" => "Build" }, sort: "Name", dir: "desc").apply(ROWS, COLUMNS).map(&:name)
  end
end
