module Commitments
  # One group's progress on a commitment (a person's alone when it isn't
  # grouped): what they owe, what each source and their adjustments credit,
  # and what remains. Members' credits pool, and source caps apply to the
  # group. In a grouped commitment, the records of relatives (people outside
  # the owing population related to members through the group relationship
  # type, such as a parent working a shift) credit the group too. Built by
  # Commitment#progress; nothing is stored.
  #
  # Part of the API for reports (see Commitment): owed, confirmed, planned,
  # remaining, met?, members, relatives and lines (the per-source breakdown).
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

    attr_reader :commitment, :members, :lines, :adjustments, :relatives

    def initialize(commitment, members, lines, adjustments, relatives = [])
      @commitment = commitment
      @members = members
      @lines = lines
      @adjustments = adjustments
      @relatives = relatives
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
    # each source in order for every member and relative, deduped across
    # sources by dedupe key (see CreditRecord), then pooled by group.
    def self.for(commitment, people)
      people = people.to_a.select { |person| commitment.group_ids_for(person.id).any? }
      return {} if people.empty?

      groups = people.map { |person| commitment.group_ids_for(person.id) }.uniq
      ids = groups.flatten
      wanted = groups.to_set
      relative_groups = commitment.group_relatives_index.select { |_id, group_ids| wanted.include?(group_ids) }
      relatives_of = relative_groups.keys.group_by { |id| relative_groups[id] }
      members = Person.where(id: ids).order(:last_name, :first_name).to_a
      relatives = relative_groups.any? ? Person.where(id: relative_groups.keys).order(:last_name, :first_name).to_a : []
      sources = commitment.commitment_sources.to_a
      kinds = sources.map(&:kind_instance)
      records = kinds.map { |kind| kind ? kind.records(ids + relative_groups.keys) : [] }
      winners = dedupe_winners(kinds, records)

      by_source = sources.each_with_index.map do |source, index|
        kept = records[index].select { |record| record.dedupe_key.nil? || (winners[record.dedupe_key] == winner_signature(record, index) && winners.delete(record.dedupe_key)) }
        [ source, kept.group_by(&:person_id) ]
      end
      adjustments = commitment.commitment_adjustments.where(person_id: ids).order(:created_at).group_by(&:person_id)

      by_group = groups.to_h do |group_ids|
        group = members.select { |member| group_ids.include?(member.id) }
        crediting = group_ids + relatives_of.fetch(group_ids, [])
        lines = by_source.map { |source, records| line(commitment, source, crediting.flat_map { |id| records[id] || [] }) }
        [ group_ids, new(commitment, group, lines, group_ids.flat_map { |id| adjustments[id] || [] }.sort_by(&:created_at),
          relatives.select { |relative| crediting.include?(relative.id) }) ]
      end
      people.to_h { |person| [ person.id, by_group[commitment.group_ids_for(person.id)] ] }
    end

    # Which record counts for each dedupe key among these records (as a
    # winner_signature), chosen among every record the same workers have
    # under that key, including ones crediting people outside this batch, so
    # a worker's place counts for the same person whoever's progress is asked
    # for. A record on someone's behalf beats one for the worker, then the
    # earlier source, then confirmed over planned.
    def self.dedupe_winners(kinds, records)
      keyed = records.flatten.select(&:dedupe_key)
      return {} if keyed.empty?

      keys = keyed.map(&:dedupe_key).to_set
      workers = keyed.map(&:worker).uniq
      candidates = kinds.each_with_index.flat_map do |kind, index|
        others = kind ? kind.records_by_workers(workers).select { |record| keys.include?(record.dedupe_key) } : []
        (records[index] + others).map { |record| [ record, index ] }
      end
      candidates.group_by { |record, _index| record.dedupe_key }.transform_values do |entries|
        winner_signature(*entries.min_by { |record, index| [ record.on_behalf? ? 0 : 1, index, record.confirmed? ? 0 : 1, record.person_id.to_s, record.label.to_s ] })
      end
    end

    def self.winner_signature(record, index)
      [ index, record.person_id, record.state, record.label ]
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
