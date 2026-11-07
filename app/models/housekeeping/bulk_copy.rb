module Housekeeping
  # "Copy selected, dates shifted": one copier per record (the type's copy:
  # class), each making a draft. The preview shows every date that moves and
  # one "Old → New" table for all the copies, picked once.
  #
  # Records copied together stay linked: when one names another in the
  # batch (a checklist requiring another), the copies are made in that
  # order and the later copy names the new one, whatever was picked. A
  # copier opts in by answering referenced_records; one that answers
  # empty_rules says what each copy leaves out.
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

    # Picks for records outside the batch; those in it become their copies.
    def replacements
      copiers.values.flat_map(&:replacements).uniq(&:key).reject { |replacement| batch_keys.include?(replacement.key) }
    end

    # [[record, [records in the batch it names]]] for those that name any.
    def links
      ordered.filter_map do |record|
        named = in_batch(record)
        [ record, named ] if named.any?
      end
    end

    # [[record, [rules]]]: rules naming something deleted, which its copy
    # leaves out.
    def left_out
      copiers.filter_map do |record, copier|
        rules = copier.respond_to?(:empty_rules) ? copier.empty_rules.to_a : []
        [ record, rules ] if rules.any?
      end
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
      made = {}
      ordered.each do |record|
        copier = copiers[record]
        own = replace.to_h.slice(*copier.replacements.map(&:key))
        in_batch(record).each { |named| own[replacement_key(named)] = made[named].id if made[named] }
        made[record] = copier.call(title: copy_title(name_of(record)), by: @user.person, replace: own)
        result[:copies] << made[record]
      rescue *copy_errors => e
        result[:failed] << [ record, e.message ]
      end
      result
    end

    private

    def batch_keys
      @batch_keys ||= ready.map { |record| replacement_key(record) }.to_set
    end

    # The other records in the batch this one's copier names.
    def in_batch(record)
      copier = copiers[record]
      return [] unless copier.respond_to?(:referenced_records)

      copier.referenced_records.select { |named| named != record && batch_keys.include?(replacement_key(named)) }
    end

    # The batch with each record after the ones it names (a cycle keeps the
    # selection's order for the records in it).
    def ordered
      @ordered ||= begin
        done = []
        visiting = Set.new
        visit = lambda do |record|
          next if done.include?(record) || visiting.include?(record)

          visiting << record
          in_batch(record).each { |named| visit.call(ready.find { |candidate| replacement_key(candidate) == replacement_key(named) }) }
          done << record
        end
        ready.each { |record| visit.call(record) }
        done
      end
    end

    # A copier says it refused with its own Refused error.
    def copy_errors
      [ ActiveRecord::RecordInvalid, (type.copier::Refused if type.copier.const_defined?(:Refused, false)) ].compact
    end
  end
end
