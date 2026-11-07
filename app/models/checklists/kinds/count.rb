module Checklists
  module Kinds
    # Do a number of something: the Commitments engine behind an item
    # (checklists spec §6.2). Each count item has a Commitment row
    # (Checklists::CountItem) holding its credit sources and adjustments; the
    # item's settings (unit, amounts, pooling, counts when) are copied into
    # it. Who owes is the checklist's population narrowed by the item's
    # rules, and the period is the item's dates, so Commitment#progress
    # answers exactly as it does for any commitment.
    #
    # Done: the progress is met. Almost: counting confirmed credit only, and
    # confirmed plus planned would reach the amount. Not yet: otherwise.
    class Count < ItemKind
      COUNTS_WHEN = [ [ "Confirmed credit reaches the amount", "confirmed" ], [ "Confirmed and planned credit together reach it", "planned" ] ].freeze

      class << self
        def label = "Count"
        def description = "Do a number of something, such as shifts or events, counted from what people do. Save it, then choose what counts"
        def uses_dates? = true

        def settings
          [
            ItemKind::Setting.new(key: :base_amount, type: :number, label: "How many", hint: "By each person, or by a group's first member"),
            ItemKind::Setting.new(key: :unit, type: :text, label: "Of what", hint: "For example shifts, events or hours"),
            ItemKind::Setting.new(key: :group_relationship_type_id, type: :choice, label: "Owe together through",
              hint: "People connected through this relationship, directly or through one person related to both, owe as one group and pool their credit",
              options: [ [ "Nobody, everyone owes on their own", "" ] ] + RelationshipType.order(:parent_label).map { |type| [ type.identifier_name, type.id ] }),
            ItemKind::Setting.new(key: :additional_amount, type: :number, label: "Each other group member adds",
              hint: "A group owes the amount plus this for each member after the first"),
            ItemKind::Setting.new(key: :counts_when, type: :choice, label: "Done when", options: COUNTS_WHEN)
          ]
        end

        def measures
          [
            ItemKind::Measure.new(key: "confirmed", label: "Confirmed", type: :number),
            ItemKind::Measure.new(key: "planned", label: "Planned", type: :number),
            ItemKind::Measure.new(key: "owed", label: "Owed", type: :number),
            ItemKind::Measure.new(key: "remaining", label: "Remaining", type: :number)
          ]
        end

        # Credit comes from activity anywhere in the item's reach, and a
        # relative's record credits a whole group, so these mark the whole
        # checklist.
        def invalidations
          [ ::Checkin, ::Event, ::Relationship, ::CommitmentSource, ::CommitmentAdjustment, ::Commitment ].map { |model| [ model, ->(_record) { :all } ] }
        end

        def validate(item)
          config = item.config
          item.errors.add(:base, "Say how many") unless config["base_amount"].to_i.positive?
          item.errors.add(:base, "Say what is counted, such as shifts") if config["unit"].blank?
          item.errors.add(:base, "Each other group member adds can't be negative") if config["additional_amount"].to_i.negative?
          if config["counts_when"].present? && COUNTS_WHEN.none? { |_, value| value == config["counts_when"] }
            item.errors.add(:base, "Choose when it's done")
          end
          if config["group_relationship_type_id"].present? && !RelationshipType.exists?(id: config["group_relationship_type_id"])
            item.errors.add(:base, "That relationship type no longer exists")
          end
          return if item.checklist.nil?

          item.errors.add(:base, "A count needs a start date, its own or the checklist's") unless Context.new(item.checklist).window_for(item).starts_on
        end

        def problems(item)
          return [ "Its count record is missing" ] if item.commitment.nil?

          sources = item.commitment.commitment_sources.to_a
          problems = []
          problems << "Nothing counts toward it yet" if sources.empty?
          problems += sources.reject(&:available?).map { |source| "#{source.label} isn't available here, so it counts nothing" }
          problems
        end

        def default_read_level(item)
          item.config["group_relationship_type_id"].present? ? "group" : "self_and_leaders"
        end

        def describe(item)
          config = item.config
          amount = config["base_amount"].to_i
          text = "#{amount} #{amount == 1 ? config["unit"].to_s.singularize : config["unit"]}"
          if config["group_relationship_type_id"].present?
            type = RelationshipType.find_by(id: config["group_relationship_type_id"])
            text += ", owed together through #{type&.identifier_name || "a relationship"}"
            text += ", plus #{config["additional_amount"].to_i} for each other member" if config["additional_amount"].to_i.positive?
          end
          text += ", planned credit counting" if config["counts_when"] == "planned"
          text
        end

        # The people among the checklist's population the item applies to
        # (default: everyone it covers).
        def owing_ids(item, covered_ids = nil)
          Population.applicable_ids(item, covered_ids || Population.new(item.checklist).person_ids)
        end

        # The item's dates as the commitment's period, in the site's time
        # zone: from the start of its first day to the end of its last (up to
        # as_of when it has no end), never past the checklist's cutoff.
        def period_for(item, as_of: nil)
          context = Context.new(item.checklist, as_of: as_of)
          window = context.window_for(item)
          from = window.start_time || Time.zone.at(0)
          to = window.ends_on ? window.ends_on.in_time_zone.end_of_day : context.as_of
          cutoff = item.checklist.cutoff_on&.in_time_zone&.end_of_day
          to = [ to, cutoff ].min if cutoff
          from..[ to, from ].max
        end

        # The commitment columns the item sets.
        def commitment_attributes(item)
          config = item.config
          window = item.checklist ? Context.new(item.checklist).window_for(item) : nil
          attributes = {
            team_id: item.checklist&.team_id,
            unit: config["unit"],
            base_amount: config["base_amount"],
            additional_amount: config["additional_amount"].to_i,
            counts_when: config["counts_when"].presence || "confirmed",
            group_relationship_type_id: config["group_relationship_type_id"].presence
          }
          if window&.starts_on
            attributes[:starts_on] = window.starts_on
            attributes[:ends_on] = [ window.ends_on || window.as_of.to_date, window.starts_on ].max
          end
          attributes
        end

        # A commitment set up to answer for this item: its own row (or an
        # unsaved one, for a draft item) with the item's settings in memory,
        # owing people and as-of moment given. Nothing is saved.
        def commitment_for(item, owing_ids: nil, as_of: nil)
          commitment = (Commitment.find_by(id: item.commitment_id) if item.commitment_id)
          commitment ||= Commitment.new(title: item.label, team_id: item.checklist.team_id, owing_team_id: item.checklist.team_id)
          commitment.assign_attributes(commitment_attributes(item).except(:starts_on, :ends_on))
          commitment.count_item = item
          commitment.count_person_ids = owing_ids || owing_ids(item)
          commitment.count_as_of = as_of
          commitment
        end

        # The next moment an answer can change with no data change: an event
        # in the period starting (planned becomes confirmed), or the start of
        # tomorrow when the item's start moves with the date.
        def next_change_at(item, context)
          period = period_for(item, as_of: context.as_of)
          team_ids = Checklists.team_subtree_ids(item.checklist.team_id)
          times = [ Event.where(team_id: team_ids, start_time: context.as_of..period.end).where("start_time > ?", context.as_of).minimum(:start_time) ]
          times << context.as_of.to_date.tomorrow.in_time_zone.beginning_of_day if item.starts_within_amount.present?
          times.compact.min
        end

        # Among person_ids, the people in the viewer's group or in a group
        # the viewer is related to through the pooling relationship (a
        # parent). nil when the item doesn't pool.
        def group_reach(item, viewer, person_ids)
          return nil if item.config["group_relationship_type_id"].blank?
          return [] if viewer.nil?

          item.count_group_reach_cache[[ viewer.id, person_ids ]] ||= begin
            commitment = commitment_for(item)
            type_id = commitment.group_relationship_type_id
            related = Relationship.where(relationship_type_id: type_id, parent_id: viewer.id).pluck(:child_id) +
              Relationship.where(relationship_type_id: type_id, child_id: viewer.id).pluck(:parent_id)
            reach = [ viewer.id ] + related
            person_ids.select { |id| commitment.group_ids_for(id).intersect?(reach) }
          end
        end

        # Recomputes the stored period of the checklist's count items'
        # commitments, so relative dates and cutoffs show on the commitment
        # too. Writes only the two dates, without callbacks.
        def sync_periods(checklist)
          checklist.checklist_items.where(kind: CountItem::COUNT).where.not(commitment_id: nil).includes(:commitment).find_each do |item|
            attributes = commitment_attributes(item).slice(:starts_on, :ends_on)
            next if attributes.empty?
            next if item.commitment.starts_on == attributes[:starts_on] && item.commitment.ends_on == attributes[:ends_on]

            item.commitment.update_columns(attributes)
          end
        end

        # Marks every checklist with a count item when a credit source's
        # watched notification fires (sign-ups, say).
        def source_changed(name)
          return unless Checklists.enabled?
          return unless Commitments.source_kinds.values.any? { |kind| kind.watches.include?(name) }

          Checklists.mark(::Checklist.refreshable.where(id: ::ChecklistItem.where(kind: CountItem::COUNT).select(:checklist_id)).to_a, :all)
        end
      end

      def evaluate(person_ids)
        commitment = self.class.commitment_for(item, owing_ids: self.class.owing_ids(item, covered_ids), as_of: context.as_of)
        progress = commitment.progress(Person.where(id: person_ids))
        earn = commitment.commitment_sources.select(&:available?).map { |source| source.kind_instance.how_to_earn.text }

        person_ids.index_with do |person_id|
          group = progress[person_id]
          next Result.exempt(item.exempt_label.presence || "Doesn't owe") unless group

          result_for(commitment, group, earn)
        end
      end

      private

      def covered_ids
        context.evaluator ? context.evaluator.covered_ids : Population.new(item.checklist).person_ids
      end

      def result_for(commitment, group, earn)
        unit = commitment.unit.to_s
        summary = "#{group.counted} of #{group.owed} #{group.owed == 1 ? unit.singularize : unit}"
        measures = { "confirmed" => group.confirmed, "planned" => group.planned, "owed" => group.owed, "remaining" => group.remaining }
        detail = detail_for(commitment, group, earn)

        if group.met?
          Result.met(summary, detail: detail, measures: measures)
        elsif !commitment.counts_planned? && group.confirmed + group.planned >= group.owed
          Result.pending(summary, detail: detail, measures: measures)
        else
          Result.not_met(summary, detail: detail, measures: measures)
        end
      end

      # The breakdown per source and adjustments, how to earn more, and the
      # size of a pooled group (never its members' names: a result shows only
      # what is about its own person).
      def detail_for(commitment, group, earn)
        parts = group.lines.map do |line|
          text = "#{line.source.label}: #{line.confirmed_credits}"
          text += " (#{line.planned_credits} planned)" if line.planned_credits.positive?
          text
        end
        parts << "Adjusted: #{format("%+d", group.adjustment_credits)}" if group.adjustments.any?
        sentence = parts.any? ? "#{parts.join("; ")}." : "Nothing counts toward it yet."
        sentence += " Shared by a group of #{group.members.size}." if group.members.size > 1
        sentence += " #{group.remaining} to go. #{earn.join(" ")}" if !group.met? && group.remaining.positive?
        sentence.strip
      end
    end
  end
end
