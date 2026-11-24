# The heading filters and sort a viewer set on a table (table_filter_controller.js),
# carried to the server by a link or button marked data-table-filter-carry,
# so a CSV, labels or totals hold the rows shown on screen:
#
#   TableFilterParams.new(params[:tf], sort: params[:tf_sort], dir: params[:tf_dir])
#     .apply(rows, "Name" => ->(row) { row.name }, "Team" => ->(row) { row.team_name })
#
# Each column maps the heading's key (its data-column-key, else its text) to
# a lambda giving the cell's text as the table shows it. Keys the columns
# don't name are ignored.
#
# This mirrors the controller's rules; change both together. A cell's value
# is its text with runs of whitespace made one space, trimmed. A column with
# values chosen keeps the rows whose value is one of them (blank is a value
# of its own); columns combine. Sorting: blanks last, numbers ($ and commas
# ignored) and dates (yyyy-mm-dd...) before text and by size, then text in
# natural order ignoring case and accents; descending reverses the
# comparison, so blanks come first. Ties keep the rows' original order in
# both directions (the controller breaks them by each row's position when
# the page loaded), so only the last sort counts.
class TableFilterParams
  DATE = /\A\d{4}-\d{2}-\d{2}/
  NUMBER_NOISE = /[$,\s]/

  attr_reader :filters, :sort, :descending

  # filters: { key => value or [values] } (params[:tf]); sort: a key;
  # dir: "desc" for descending, else ascending. Anything else, such as a
  # hand-edited ?tf=x, counts as nothing carried.
  def initialize(filters, sort: nil, dir: nil)
    filters = filters.to_unsafe_h if filters.respond_to?(:to_unsafe_h)
    filters = {} unless filters.is_a?(Hash)
    @filters = filters.to_h { |key, values| [ key.to_s, Array(values).map { |value| clean(value) }.to_set ] }
      .reject { |_, values| values.empty? }
    @sort = sort.presence if sort.is_a?(String)
    @descending = dir.to_s == "desc"
  end

  def active?
    filters.any? || sort.present?
  end

  # The rows the table shows, in its order. columns: { key => ->(row) { text } }.
  def apply(rows, columns)
    columns = columns.to_h.transform_keys(&:to_s)
    kept = rows.select do |row|
      filters.all? { |key, values| !columns.key?(key) || values.include?(clean(columns[key].call(row))) }
    end
    return kept unless sort && columns.key?(sort)

    direction = descending ? -1 : 1
    kept.each_with_index
      .map { |row, index| [ sort_key(clean(columns[sort].call(row))), index, row ] }
      .sort { |(a, i), (b, j)| (direction * compare(a, b)).nonzero? || i <=> j }
      .map(&:last)
  end

  private

  def clean(value)
    value.to_s.gsub(/\s+/, " ").strip
  end

  # { number:, text: } like the controller's sortKey.
  def sort_key(text)
    number = text.gsub(NUMBER_NOISE, "")
    if number != "" && number.match?(/\A[+-]?(\d+\.?\d*|\.\d+)(e[+-]?\d+)?\z/i)
      { number: number.to_f, text: text }
    elsif text.match?(DATE) && (time = parse_time(text))
      { number: time, text: text }
    else
      { text: text }
    end
  end

  # Milliseconds, as Date.parse gives, so dates and numbers compare alike.
  def parse_time(text)
    time = Time.zone.parse(text)
    time && time.to_f * 1000
  rescue ArgumentError
    nil
  end

  def compare(a, b)
    if a[:text].empty? != b[:text].empty?
      a[:text].empty? ? 1 : -1
    elsif a[:number] && b[:number]
      a[:number] <=> b[:number]
    elsif a[:number] || b[:number]
      a[:number] ? -1 : 1
    else
      natural(a[:text]) <=> natural(b[:text])
    end
  end

  # localeCompare(..., { numeric: true, sensitivity: "base" }), near enough:
  # digit runs by size, the rest without case or accents (letters in any
  # script kept, so Cyrillic sorts by its alphabet).
  def natural(text)
    text.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.scan(/\d+|\D+/).map do |part|
      part.match?(/\A\d/) ? [ 0, part.to_i ] : [ 1, part ]
    end
  end
end
