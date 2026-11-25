require "csv"

# The file source's CSV layout: Download template gives the header row, and
# Accounting::Files::Reader reads files in it.
class Accounting::Files::Template
  COLUMNS = %w[ customer role number date due_date item total balance applied_to description ].freeze

  def self.csv
    CSV.generate_line(COLUMNS)
  end
end
