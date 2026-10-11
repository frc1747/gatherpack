module Commitments
  # One person's progress on a commitment: what they owe, what each source
  # and their adjustments credit, and what remains. Built by
  # Commitment#progress; nothing is stored.
  class Progress
    # One source's part of a person's progress. Quantities are the records'
    # summed quantities after dedupe; credits apply the source's ratio and
    # cap. planned_credits is what the planned records would add.
    Line = Struct.new(:source, :records, :confirmed_quantity, :planned_quantity, :confirmed_credits, :planned_credits, :partial, :capped,
      keyword_init: true) do
      def available?
        source.available?
      end
    end

    attr_reader :commitment, :person, :lines, :adjustments

    def initialize(commitment, person, lines, adjustments)
      @commitment = commitment
      @person = person
      @lines = lines
      @adjustments = adjustments
    end

    def owed
      commitment.base_amount
    end

    def adjustment_credits
      adjustments.sum(&:credits)
    end

    # Confirmed source credit plus adjustments.
    def confirmed
      lines.sum(&:confirmed_credits) + adjustment_credits
    end

    def planned
      lines.sum(&:planned_credits)
    end

    # What completes the commitment, by its counts_when setting.
    def counted
      commitment.counts_planned? ? confirmed + planned : confirmed
    end

    def remaining
      [ owed - counted, 0 ].max
    end

    def met?
      counted >= owed
    end

    # Not met, and nothing planned toward it.
    def nothing_planned?
      !met? && planned.zero?
    end

    # Builds every person's progress at once: records from each source in
    # order, deduped across sources by person and dedupe key.
    def self.for(commitment, people)
      people = people.to_a
      ids = people.map(&:id)
      seen = Set.new

      by_source = commitment.commitment_sources.map do |source|
        kind = source.kind_instance
        records = kind ? kind.records(ids).sort_by { |record| record.confirmed? ? 0 : 1 } : []
        kept = records.select { |record| record.dedupe_key.nil? || seen.add?([ record.person_id, record.dedupe_key ]) }
        [ source, kept.group_by(&:person_id) ]
      end
      adjustments = commitment.commitment_adjustments.where(person_id: ids).order(:created_at).group_by(&:person_id)

      people.to_h do |person|
        lines = by_source.map { |source, records| line(commitment, source, records[person.id] || []) }
        [ person.id, new(commitment, person, lines, adjustments[person.id] || []) ]
      end
    end

    def self.line(commitment, source, records)
      confirmed_quantity = records.select(&:confirmed?).sum(&:quantity)
      planned_quantity = records.reject(&:confirmed?).sum(&:quantity)
      confirmed_credits = source.credit_for(confirmed_quantity)
      total_credits = source.credit_for(confirmed_quantity + planned_quantity)
      counted_quantity = commitment.counts_planned? ? confirmed_quantity + planned_quantity : confirmed_quantity
      capped = source.capped?(counted_quantity)

      Line.new(source: source, records: records.sort_by(&:date), confirmed_quantity: confirmed_quantity, planned_quantity: planned_quantity,
        confirmed_credits: confirmed_credits, planned_credits: total_credits - confirmed_credits,
        partial: capped ? 0 : counted_quantity % source.per, capped: capped)
    end
  end
end
