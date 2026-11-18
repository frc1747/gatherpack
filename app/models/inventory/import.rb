require "csv"

# CSV import of items (inventory spec §3.11), for inventory managers. Each
# row names an item; a row matching an existing item by manufacturer part
# number (or by name when it has none) updates it rather than adding
# another. A row with a quantity records an "added" change, reason
# "Imported", at the place its code names. A unit must name a row of the
# stock units list (by name or plural). The only bulk write in inventory.
#
#   import = Inventory::Import.new(person:, team_id:, text: csv)
#   import.valid?          # the file and team
#   import.rows            # the preview: Row#action, #problems
#   import.apply!          # => Result(created, updated, skipped)
module Inventory
  class Import
    include ActiveModel::Model

    MAX_ROWS = 2000
    REASON = "Imported"

    # Column → accepted headers (compared without case, spaces or
    # punctuation).
    COLUMNS = {
      name: [ "name", "item" ],
      category: [ "category" ],
      manufacturer: [ "manufacturer" ],
      manufacturer_part_number: [ "manufacturer part number", "mpn", "part number" ],
      unit: [ "unit" ],
      vendor: [ "vendor", "vendor name" ],
      vendor_part_number: [ "vendor part number" ],
      link: [ "link", "url" ],
      place_code: [ "place code", "place", "location code", "code" ],
      quantity: [ "quantity", "qty", "count" ],
      reorder_point: [ "reorder point", "order more at" ],
      reorder_quantity: [ "reorder quantity", "order how many" ]
    }.freeze

    Row = Struct.new(:number, :values, :item, :location, :problems, keyword_init: true) do
      def action
        return :skip if problems.any?

        item ? :update : :create
      end

      def quantity
        values[:quantity].presence&.to_i
      end
    end

    Result = Struct.new(:created, :updated, :skipped, keyword_init: true)

    attr_accessor :person, :team_id, :text

    validates :text, presence: { message: "is empty: choose a CSV file" }
    validate :team_managed
    validate :readable

    def team
      @team ||= Team.find_by(id: team_id)
    end

    def headers
      parsed && @headers
    end

    # The preview: one Row per line of the file.
    def rows
      @rows ||= begin
        seen = {}
        (parsed || []).each_with_index.map do |values, index|
          row = Row.new(number: index + 2, values: values, problems: [])
          check(row, seen)
          row
        end
      end
    end

    def creating
      rows.count { |row| row.action == :create }
    end

    def updating
      rows.count { |row| row.action == :update }
    end

    def problem_rows
      rows.select { |row| row.action == :skip }
    end

    # Writes every row without a problem, each in its own transaction.
    def apply!
      raise Inventory::Refused, errors.full_messages.to_sentence unless valid?

      result = Result.new(created: 0, updated: 0, skipped: problem_rows.map { |row| "row #{row.number}" })
      rows.reject { |row| row.action == :skip }.each do |row|
        created = row.item.nil?
        ActiveRecord::Base.transaction { write(row) }
        created ? result.created += 1 : result.updated += 1
      rescue ActiveRecord::RecordInvalid, Inventory::Refused => error
        result.skipped << "row #{row.number} (#{error.message})"
      end
      result
    end

    private

    def access
      Inventory::Access.for(person)
    end

    def parsed
      return @parsed if defined?(@parsed)

      @parsed = nil
      table = CSV.parse(text.to_s.dup.force_encoding(Encoding::UTF_8).scrub.delete_prefix("\uFEFF"), headers: true)
      @headers = table.headers.compact
      columns = @headers.to_h { |header| [ header, column_for(header) ] }
      @parsed = table.first(MAX_ROWS + 1).map do |line|
        line.to_h.each_with_object({}) do |(header, value), values|
          key = columns[header]
          values[key] = value.to_s.strip if key && !values[key].present?
        end
      end
    rescue CSV::MalformedCSVError => error
      @parse_error = error.message
      @parsed = nil
    end

    def column_for(header)
      plain = header.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
      COLUMNS.find { |_key, names| names.include?(plain) }&.first
    end

    def readable
      return if text.blank?

      if parsed.nil?
        errors.add(:base, "The file isn't a CSV we can read#{": #{@parse_error}" if @parse_error}")
      elsif !headers.any? { |header| column_for(header) == :name }
        errors.add(:base, "The first line needs a Name column")
      elsif parsed.size > MAX_ROWS
        errors.add(:base, "Import at most #{MAX_ROWS} rows at a time")
      end
    end

    def team_managed
      errors.add(:team_id, "must be a team whose inventory you manage") unless team && access.manages?(team.id)
    end

    def check(row, seen)
      values = row.values
      if values[:name].blank?
        row.problems << "No name"
        return
      end

      row.item = match(values)
      key = (values[:manufacturer_part_number].presence || values[:name]).downcase
      row.problems << "Same item as row #{seen[key]}" if seen[key]
      seen[key] ||= row.number

      %i[quantity reorder_point reorder_quantity].each do |column|
        next if values[column].blank? || values[column].match?(/\A\d+\z/)

        row.problems << "#{column.to_s.humanize} must be a whole number"
      end

      if values[:place_code].present?
        row.location = place_for(values[:place_code])
        row.problems << "Unknown place code #{values[:place_code]}" if row.location.nil?
      elsif row.quantity.to_i.positive? && !row.item&.default_location
        row.problems << "A quantity needs a place code"
      end
      if values[:unit].present? && StockUnit.active.named(values[:unit]).nil?
        row.problems << "Unknown unit #{values[:unit]}: add it to the stock units first"
      end
      row.problems << "#{row.item.name} is tracked: add its units instead" if row.item&.tracked? && row.quantity.to_i.positive?
      row.problems << "You don't manage #{row.item.name}" if row.item && !access.manages?(row.item.team_id)
    end

    # An existing item: by manufacturer part number, or by name when the
    # row has none.
    def match(values)
      scope = access.admin? ? Item.all : Item.where(team_id: access.visible_team_ids.to_a)
      if values[:manufacturer_part_number].present?
        scope.where("LOWER(manufacturer_part_number) = ?", values[:manufacturer_part_number].downcase).first
      else
        scope.where("LOWER(name) = ?", values[:name].downcase).where(manufacturer_part_number: [ nil, "" ]).first
      end
    end

    # An active storage place the person sees with this code. A code is
    # unique within its top-level place, so a code used in two shops is
    # ambiguous and not matched.
    def place_for(code)
      places = Location.active.storage.where("LOWER(code) = ?", code.downcase)
      places = places.where(team_id: access.visible_team_ids.to_a) unless access.admin?
      places.limit(2).to_a.then { |found| found.one? ? found.first : nil }
    end

    def write(row)
      values = row.values
      item = row.item || Item.new(team: team, name: values[:name])
      item.lock! if item.persisted?
      {
        category: values[:category], manufacturer: values[:manufacturer],
        manufacturer_part_number: values[:manufacturer_part_number], stock_unit: StockUnit.active.named(values[:unit]),
        url: (values[:link] if values[:vendor].blank?),
        reorder_point: values[:reorder_point], reorder_quantity: values[:reorder_quantity]
      }.each { |attribute, value| item.public_send(:"#{attribute}=", value) if value.present? }
      item.home_location ||= row.location
      item.save!

      write_source(item, values) if values[:vendor].present?
      return unless row.quantity.to_i.positive?

      StockMovement.record!(kind: :added, item: item, location: row.location || item.default_location,
        quantity: row.quantity, reason: REASON, person: person)
    end

    def write_source(item, values)
      source = item.item_sources.find { |existing| existing.vendor_name.casecmp?(values[:vendor]) } ||
        item.item_sources.build(vendor_name: values[:vendor], preferred: item.item_sources.none?)
      source.vendor_part_number = values[:vendor_part_number] if values[:vendor_part_number].present?
      source.url = values[:link] if values[:link].present?
      source.save!
    end
  end
end
