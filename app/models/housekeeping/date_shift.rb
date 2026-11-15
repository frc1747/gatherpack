module Housekeeping
  # Shifting dates forward when something is copied, and the "Old → New"
  # table for records named with a year (a badge "Safety 2026" becomes
  # "Safety 2027" when that exists). Included by each copier
  # (Checklists::Copier; forms and registrations the same way), which says
  # which of its dates shift and which records it names; Housekeeping::BulkCopy
  # gathers the table for many copies at once.
  #
  # The includer sets @shift_months.
  module DateShift
    YEAR = /\b(19|20)\d{2}\b/

    # A record named with a year, and the record named with the year
    # shifted (nil when none exists). key is what a form's pick sends.
    Replacement = Struct.new(:key, :record, :proposed, keyword_init: true) do
      def model = record.class
    end

    def shift_months
      @shift_months.to_i
    end

    def shift_years
      (shift_months / 12.0).round
    end

    def shift(date)
      date && date + shift_months.months
    end

    # The name with each year moved on (unchanged when it has none).
    def shift_name(name)
      name.to_s.gsub(YEAR) { |year| (year.to_i + shift_years).to_s }
    end

    # The title a copy gets: the name with its years shifted, or "(copy)"
    # added when it names no year.
    def copy_title(name)
      name.to_s.match?(YEAR) ? shift_name(name) : "#{name} (copy)"
    end

    # The replacements for records named with a year.
    def replacements_for(records)
      records.compact.uniq.filter_map do |record|
        name = name_of(record)
        next unless name.to_s.match?(YEAR)

        Replacement.new(key: replacement_key(record), record: record, proposed: find_named(record.class, shift_name(name)))
      end
    end

    def replacement_key(record)
      "#{record.class.name}:#{record.id}"
    end

    def name_of(record)
      record.respond_to?(:title) ? record.title : record.try(:name)
    end

    def find_named(model, name)
      column = model.column_names.include?("title") ? :title : :name
      model.find_by(column => name)
    end
  end
end
