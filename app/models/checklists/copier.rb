module Checklists
  # "Copy checklist" (spec §9.3): duplicates the population, items (with
  # their rules), grants and organizers into a new draft, with dates shifted
  # and named references replaced, after a person confirms both. Excuses,
  # attestations, results and recorded lists aren't copied.
  #
  #   copier = Checklists::Copier.new(checklist, shift_months: 12)
  #   copier.date_changes   # [DateChange] old -> proposed, editable
  #   copier.replacements   # [Replacement] records named with a year
  #   copier.call(title:, by:, dates: { key => date }, replace: { key => id })
  class Copier
    include ::Housekeeping::DateShift

    DateChange = Struct.new(:key, :label, :old, :proposed, keyword_init: true)
    Replacement = ::Housekeeping::DateShift::Replacement

    # The copy was refused: by may not set up items (labels; their kind's
    # authorable_by? said no to the copied config, replacements included) or
    # make grants (holder names) it would hold. Nothing is saved.
    class Refused < StandardError
      attr_reader :items, :grants

      def initialize(items, grants)
        @items = items
        @grants = grants
        super("Can't copy #{(items + grants).to_sentence}")
      end
    end

    attr_reader :checklist

    def initialize(checklist, shift_months: 12)
      @checklist = checklist
      @shift_months = shift_months.to_i
    end

    # Every fixed date, shifted. Relative dates ("within the last N") stay.
    def date_changes
      changes = %w[starts_on ends_on].filter_map do |field|
        old = checklist.public_send(field)
        DateChange.new(key: "checklist.#{field}", label: "Checklist #{field.humanize(capitalize: false)}", old: old, proposed: shift(old)) if old
      end
      items.each do |item|
        %w[starts_on ends_on due_on].each do |field|
          old = item.public_send(field)
          changes << DateChange.new(key: "#{item.id}.#{field}", label: "#{item.label}: #{field.humanize(capitalize: false)}", old: old, proposed: shift(old)) if old
        end
        Array(item.kind_class&.copy_dates(item)).each do |entry|
          old = entry[:value]
          changes << DateChange.new(key: "#{item.id}.config.#{entry[:key]}", label: "#{item.label}: #{entry[:label].to_s.downcase_first}", old: old, proposed: shift(old)) if old
        end
      end
      changes
    end

    # Badges, teams, checklists... named with a year, matched to the name
    # with the year shifted when one exists.
    def replacements
      replacements_for(referenced_records)
    end

    # Every record the copy names: what its items, rules and grants refer
    # to. Any of them can be swapped through call's replace:, not only those
    # named with a year (a copy made alongside, say).
    def referenced_records
      @referenced_records ||= begin
        records = items.flat_map do |item|
          Array(item.kind_class&.references).flat_map { |key, _| item.kind_class.referenced_records(item, key) }
        end
        rules = checklist.checklist_rules.includes(:team, :badge).to_a
        records += rules.flat_map { |rule| [ rule.team, rule.badge ] }
        records += checklist.checklist_grants.includes(:team, :badge).flat_map { |grant| [ grant.team, grant.badge ] }
        records.compact.uniq
      end
    end

    # Rules left with no target (a deleted person, team or badge), which a
    # copy leaves out.
    def empty_rules
      checklist.checklist_rules.includes(:team, :badge, :person, :item).reject(&:target)
    end

    # dates: { key => Date or string } overriding the proposals (blank keeps
    # the old date); replace: { key => id } (blank keeps the record). Raises
    # Refused when by couldn't set up a copied item or make a copied grant.
    def call(title:, by:, dates: {}, replace: {})
      dates = date_changes.to_h { |change| [ change.key, change.proposed ] }.merge(dates.to_h.transform_values { |value| cast_date(value) }.compact)
      known = referenced_records.to_h { |record| [ replacement_key(record), record.class ] }
      replace = replace.to_h.compact_blank.select { |key, id| known[key]&.exists?(id: id) }

      Checklist.transaction do
        copy = checklist.dup
        copy.assign_attributes(title: title.presence || "#{checklist.title} (copy)", status: :draft, created_by: by,
          computed_at: nil, next_refresh_at: nil)
        %w[starts_on ends_on].each { |field| copy[field] = dates.fetch("checklist.#{field}", copy[field]) }
        copy.save!
        checklist.checklist_organizers.where.not(person_id: by&.id).find_each do |organizer|
          copy.checklist_organizers.create(person_id: organizer.person_id)
        end

        # The population first: a kind's authorable_by? may ask who the copy covers.
        checklist.population_rules.each { |rule| copy_rule(rule, copy, nil, replace) }
        item_ids = {}
        @refused_items = []
        checklist.top_level_items.each { |item| copy_item(item, copy, nil, dates, replace, item_ids, by) }
        raise Refused.new(@refused_items, []) if @refused_items.any?

        refused_grants = checklist.checklist_grants.filter_map do |grant|
          new_grant = copy.checklist_grants.new(badge_id: swap(grant.badge, replace), team_id: swap(grant.team, replace),
            access: grant.access, item_ids: grant.item_ids.filter_map { |id| item_ids[id] }, created_by: by)
          refused = by ? new_grant.refused_items(by) : []
          next "#{new_grant.holder_name}' #{new_grant.access} access to #{refused.map(&:label).to_sentence}" if refused.any?

          new_grant.save!
          nil
        end
        raise Refused.new([], refused_grants) if refused_grants.any?

        copy
      end
    end

    private

    def items
      @items ||= checklist.checklist_items.order(:position).to_a
    end

    def swap(record, replace)
      return if record.nil?

      replace[replacement_key(record)].presence || record.id
    end

    # Each copied item is checked against by (ItemKind.authorable_by? on the
    # copy's config) before it's saved. Once one is refused nothing more is
    # saved, but the rest are still checked so the refusal names them all.
    def copy_item(item, copy, parent, dates, replace, item_ids, by)
      new_item = item.dup
      new_item.assign_attributes(checklist: copy, parent: parent, config: copy_config(item, dates, replace))
      %w[starts_on ends_on due_on].each { |field| new_item[field] = dates.fetch("#{item.id}.#{field}", new_item[field]) }
      kind = new_item.kind_class
      @refused_items << new_item.label if by && kind && !kind.authorable_by?(new_item, by)
      if @refused_items.empty?
        new_item.save!
        item_ids[item.id] = new_item.id
        item.checklist_rules.each { |rule| copy_rule(rule, copy, new_item, replace) }
      end
      item.children.each { |child| copy_item(child, copy, new_item, dates, replace, item_ids, by) }
    end

    def copy_config(item, dates, replace)
      config = item.config.deep_dup
      Array(item.kind_class&.references).each do |key, model_name|
        next unless config.key?(key)

        swap_id = ->(id) { replace["#{model_name}:#{id}"].presence || id }
        config[key] = config[key].is_a?(Array) ? config[key].map(&swap_id) : swap_id.call(config[key])
      end
      kind = item.kind_class
      return config unless kind

      prefix = "#{item.id}.config."
      own = kind.copy_dates(item).map { |entry| entry[:key].to_s }
      picked = own.to_h { |key| [ key, dates["#{prefix}#{key}"] ] }.compact
      picked.any? ? kind.apply_copy_dates(item, config, picked) : config
    end

    # Rules whose person, team or badge was deleted match nobody; they're
    # left out of the copy (see empty_rules).
    def copy_rule(rule, copy, item, replace)
      return if rule.target.nil?

      copy.checklist_rules.create!(item: item, effect: rule.effect, target_type: rule.target_type,
        team_id: swap(rule.team, replace), badge_id: swap(rule.badge, replace), person_id: rule.person_id,
        include_managers: rule.include_managers)
    end

    def cast_date(value)
      return value if value.is_a?(Date)

      value.present? ? Date.iso8601(value.to_s) : nil
    rescue Date::Error
      nil
    end
  end
end
