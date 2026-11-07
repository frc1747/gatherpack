module Housekeeping
  # "Copy selected, dates shifted": one copier per record (the type's copy:
  # class), each making a draft. The preview shows every date that moves and
  # one "Old → New" table for all the copies, picked once.
  #
  #   copy = Housekeeping::BulkCopy.new(type, records, user, shift_months: 12)
  #   copy.date_changes    # [[record, [DateChange]]]
  #   copy.replacements    # [Replacement], one per named record
  #   copy.apply!(replace: { key => id })   # => { copies: [...], failed: [[record, reason]] }
  class BulkCopy
    include DateShift

    attr_reader :type, :ready, :skipped

    def initialize(type, records, user, shift_months: 12)
      @type = type
      @user = user
      @shift_months = shift_months.to_i
      @ready = []
      @skipped = []
      records.each do |record|
        if type.permitted?(user, record, :copy)
          @ready << record
        else
          @skipped << Preview::Skip.new(record, "you can't copy it")
        end
      end
    end

    def copiers
      @copiers ||= ready.to_h { |record| [ record, type.copier.new(record, shift_months: shift_months) ] }
    end

    def date_changes
      copiers.map { |record, copier| [ record, copier.date_changes ] }
    end

    def replacements
      copiers.values.flat_map(&:replacements).uniq(&:key)
    end

    def sentence
      text = "#{ready.size} #{ready.size == 1 ? type.label.downcase.singularize : type.label.downcase} will be copied as drafts, dates moved #{shift_description}."
      text += " #{skipped.size} skipped." if skipped.any?
      text
    end

    def shift_description
      months = shift_months.abs
      amount = (months % 12).zero? ? "#{months / 12} #{"year".pluralize(months / 12)}" : "#{months} #{"month".pluralize(months)}"
      shift_months.negative? ? "back #{amount}" : "on #{amount}"
    end

    # Each copy is made on its own; one that's refused is reported, not
    # fatal to the others. Copies get the name with its years shifted.
    def apply!(replace: {})
      result = { copies: [], failed: [] }
      copiers.each do |record, copier|
        own = replace.to_h.slice(*copier.replacements.map(&:key))
        result[:copies] << copier.call(title: copy_title(name_of(record)), by: @user.person, replace: own)
      rescue *copy_errors => e
        result[:failed] << [ record, e.message ]
      end
      result
    end

    private

    # A copier says it refused with its own Refused error.
    def copy_errors
      [ ActiveRecord::RecordInvalid, (type.copier::Refused if type.copier.const_defined?(:Refused, false)) ].compact
    end
  end
end
