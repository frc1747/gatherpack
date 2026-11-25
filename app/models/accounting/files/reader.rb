require "csv"

# Reads an uploaded CSV in the file source's layout (Accounting::Files::TEMPLATE)
# into the raw records Gateway::FileSource yields, by entity type, plus the
# rows' errors. Customers and items are made from the distinct values in
# their columns. A charge's blank balance is its total less what the file's
# payments and credits apply to it.
class Accounting::Files::Reader
  ROLES = %w[ charge payment credit refund receipt ].freeze
  REQUIRED = %w[ customer role total ].freeze
  # Rows whose applied_to lowers a charge's computed balance.
  APPLYING = %w[ payment credit ].freeze
  MAX_ROWS = 5000

  Result = Data.define(:records, :errors, :row_count)

  def initialize(content)
    @content = content.to_s.delete_prefix("﻿")
    @errors = []
  end

  def read
    table = CSV.parse(@content, headers: true, header_converters: ->(header) { header.to_s.strip.downcase.gsub(/[\s-]+/, "_") })
    missing = REQUIRED - table.headers.compact
    return failed("The file has no #{missing.join(', ')} column. Start from the template.") if missing.any?

    rows = table.each.with_index(2).reject { |row, _| row.fields.all?(&:blank?) }
    return failed("The file has more than #{MAX_ROWS} rows.") if rows.size > MAX_ROWS

    parsed = rows.map { |row, line| parse_row(row, line) }
    check_numbers(parsed)
    apply_amounts(parsed)
    Result.new(records: records_for(parsed), errors: @errors, row_count: parsed.size)
  rescue CSV::MalformedCSVError => e
    failed("The file isn't a CSV the reader understands: #{e.message}")
  end

  private
    def failed(message)
      Result.new(records: {}, errors: [ { "row" => nil, "message" => message } ], row_count: 0)
    end

    def error(line, message)
      @errors << { "row" => line, "message" => message }
    end

    def parse_row(row, line)
      cell = ->(name) { row[name].to_s.strip }
      role = cell.call("role").downcase
      parsed = { line: line, role: role, customer: cell.call("customer"), number: cell.call("number").presence,
                 item: cell.call("item").presence, description: cell.call("description").presence }

      error(line, "No customer.") if parsed[:customer].blank?
      error(line, "Unknown role \"#{cell.call('role')}\": use #{ROLES.to_sentence(last_word_connector: ' or ')}.") unless ROLES.include?(role)
      error(line, "A charge needs a number.") if role == "charge" && parsed[:number].blank?

      parsed[:date] = date(cell.call("date"), line)
      parsed[:due_date] = date(cell.call("due_date"), line)
      parsed[:total] = cents(cell.call("total"), line, "total")
      error(line, "No total.") if cell.call("total").blank?
      parsed[:balance] = cents(cell.call("balance"), line, "balance") if role == "charge"
      if parsed[:balance] && parsed[:total] && parsed[:balance] > parsed[:total]
        error(line, "The balance is more than the total.")
      end
      parsed[:applied_to] = applied_to(cell.call("applied_to"), line)
      parsed[:cells] = [ role, parsed[:customer].downcase, parsed[:number], cell.call("date"), parsed[:item].to_s.downcase,
                         cell.call("total"), cell.call("applied_to"), parsed[:description] ]
      parsed
    end

    def date(text, line)
      return nil if text.blank?

      parsed = text.match?(%r{\A\d{1,2}/\d{1,2}/\d{4}\z}) ? Date.strptime(text, "%m/%d/%Y") : Date.iso8601(text)
      parsed.iso8601
    rescue Date::Error
      error(line, "\"#{text}\" isn't a date: use 2026-09-01 or 9/1/2026.")
      nil
    end

    def cents(text, line, column)
      return nil if text.blank?

      plain = text.delete("$, ")
      unless plain.match?(/\A\d+(\.\d{1,2})?\z/)
        error(line, "\"#{text}\" isn't an amount for #{column}: use a number like 150 or 150.00, never below zero.")
        return nil
      end
      (BigDecimal(plain) * 100).to_i
    end

    # "1042" or "1042:50.00;1043:25.00": charge numbers, each with an amount
    # or not.
    def applied_to(text, line)
      text.split(";").map(&:strip).compact_blank.map do |part|
        number, amount = part.split(":", 2).map(&:strip)
        { number: number, amount: (cents(amount, line, "applied_to") if amount.present?) }
      end
    end

    def check_numbers(parsed)
      parsed.reject { |row| row[:number].nil? }.group_by { |row| [ row[:role], row[:number] ] }.each do |(role, number), rows|
        next if rows.one?

        rows.each { |row| error(row[:line], "#{role.capitalize} number #{number} is used twice (rows #{rows.map { |r| r[:line] }.join(', ')}).") }
      end

      charges = parsed.select { |row| row[:role] == "charge" }.map { |row| row[:number] }.to_set
      parsed.each do |row|
        next if row[:applied_to].empty?

        if row[:role].in?(%w[ charge receipt ])
          error(row[:line], "Only payments, credits and refunds are applied to charges.")
          next
        end
        row[:applied_to].each do |applied|
          error(row[:line], "Applied to #{applied[:number]}, which isn't a charge number in this file.") unless charges.include?(applied[:number])
        end
      end
    end

    # Works out how much each payment, credit and refund applies to each
    # charge, in file order: amounts given first, then the rest of the row's
    # total to the charges listed without one, each up to what's still open
    # on it. What's left is the row's unapplied amount.
    def apply_amounts(parsed)
      charges = parsed.select { |row| row[:role] == "charge" }.index_by { |row| row[:number] }
      open = charges.transform_values { |charge| charge[:total].to_i }

      parsed.each do |row|
        next if row[:applied_to].empty? || row[:total].nil?

        left = row[:total] - row[:applied_to].sum { |applied| applied[:amount].to_i }
        if left.negative?
          error(row[:line], "Applies more than its total.")
          next
        end
        row[:applied_to].each do |applied|
          next unless charges.key?(applied[:number])

          applied[:amount] ||= [ left, open[applied[:number]].clamp(0..) ].min.tap { |amount| left -= amount }
          open[applied[:number]] -= applied[:amount] if APPLYING.include?(row[:role])
        end
        row[:unapplied] = left
      end

      charges.each_value do |charge|
        next if charge[:balance] || charge[:total].nil?

        if open[charge[:number]].negative?
          error(charge[:line], "More is applied to charge #{charge[:number]} than its total.")
        else
          charge[:balance] = open[charge[:number]]
        end
      end
    end

    def records_for(parsed)
      records = Gateway::FileSource::ENTITY_ROLES.keys.index_with { [] }
      parsed.each do |row|
        key = row[:customer].downcase
        records["customer"] << { "id" => key, "label" => row[:customer] } unless key.blank? || records["customer"].any? { |customer| customer["id"] == key }
        item = row[:item]&.downcase
        records["item"] << { "id" => item, "name" => row[:item] } unless item.nil? || records["item"].any? { |existing| existing["id"] == item }
      end

      repeats = Hash.new(0)
      parsed.each do |row|
        next unless records.key?(row[:role])

        records[row[:role]] << transaction(row, repeats)
      end
      records
    end

    def transaction(row, repeats)
      {
        "id" => row[:number] || numberless_id(row, repeats), "customer" => row[:customer].downcase, "number" => row[:number],
        "date" => row[:date], "due_date" => row[:due_date], "item" => row[:item]&.downcase, "item_name" => row[:item],
        "total_cents" => row[:total], "balance_cents" => (row[:role] == "receipt" ? 0 : row[:balance]),
        "applied_to" => row[:applied_to].map { |applied| { "external_id" => applied[:number], "amount_cents" => applied[:amount].to_i } },
        "unapplied_cents" => (row[:role].in?(APPLYING) ? row.fetch(:unapplied, row[:total]) : nil), "description" => row[:description]
      }
    end

    # A row without a number is known by its cells, and a second identical
    # row by the same cells and a count.
    def numberless_id(row, repeats)
      digest = Digest::SHA256.hexdigest(row[:cells].join("\u0000"))[0, 16]
      repeats[digest] += 1
      repeats[digest] > 1 ? "row-#{digest}-#{repeats[digest]}" : "row-#{digest}"
    end
end
