module Commitments
  # One group's progress on a commitment (a person's alone when it isn't
  # grouped): what they owe, what each source and their adjustments credit,
  # and what remains. Members' credits pool, and source caps apply to the
  # group. Built by Commitment#progress; nothing is stored.
  #
  # Part of the API for reports (see Commitment): owed, confirmed, planned,
  # remaining, met?, members and lines (the per-source breakdown).
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

    attr_reader :commitment, :members, :lines, :adjustments

    def initialize(commitment, members, lines, adjustments)
      @commitment = commitment
      @members = members
      @lines = lines
      @adjustments = adjustments
    end

    # The group's first member by name, which identifies its row.
    def person
      members.first
    end

    # base_amount for the first member, additional_amount for each other.
    def owed
      commitment.base_amount + commitment.additional_amount * (members.size - 1)
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

    # Builds the progress of these people's groups at once, keyed by person
    # id (people the commitment doesn't cover are left out): records from
    # each source in order for every member, deduped across sources by
    # person and dedupe key, then pooled by group.
    def self.for(commitment, people)
      people = people.to_a.select { |person| commitment.group_ids_for(person.id).any? }
      groups = people.map { |person| commitment.group_ids_for(person.id) }.uniq
      ids = groups.flatten
      members = Person.where(id: ids).order(:last_name, :first_name).to_a
      seen = Set.new

      by_source = commitment.commitment_sources.map do |source|
        kind = source.kind_instance
        records = kind ? kind.records(ids).sort_by { |record| record.confirmed? ? 0 : 1 } : []
        kept = records.select { |record| record.dedupe_key.nil? || seen.add?([ record.person_id, record.dedupe_key ]) }
        [ source, kept.group_by(&:person_id) ]
      end
      adjustments = commitment.commitment_adjustments.where(person_id: ids).order(:created_at).group_by(&:person_id)

      by_group = groups.to_h do |group_ids|
        group = members.select { |member| group_ids.include?(member.id) }
        lines = by_source.map { |source, records| line(commitment, source, group_ids.flat_map { |id| records[id] || [] }) }
        [ group_ids, new(commitment, group, lines, group_ids.flat_map { |id| adjustments[id] || [] }.sort_by(&:created_at)) ]
      end
      people.to_h { |person| [ person.id, by_group[commitment.group_ids_for(person.id)] ] }
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
