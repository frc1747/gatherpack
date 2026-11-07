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
    YEAR = /\b(19|20)\d{2}\b/

    DateChange = Struct.new(:key, :label, :old, :proposed, keyword_init: true)
    Replacement = Struct.new(:key, :record, :proposed, keyword_init: true) do
      def model = record.class
    end

    attr_reader :checklist, :shift_months

    def initialize(checklist, shift_months: 12)
      @checklist = checklist
      @shift_months = shift_months.to_i
    end

    # Every fixed date, shifted. Relative dates ("within the last N") stay.
    def date_changes
      changes = %w[starts_on ends_on cutoff_on].filter_map do |field|
        old = checklist.public_send(field)
        DateChange.new(key: "checklist.#{field}", label: "Checklist #{field.humanize(capitalize: false)}", old: old, proposed: shift(old)) if old
      end
      items.each do |item|
        %w[starts_on ends_on due_on].each do |field|
          old = item.public_send(field)
          changes << DateChange.new(key: "#{item.id}.#{field}", label: "#{item.label}: #{field.humanize(capitalize: false)}", old: old, proposed: shift(old)) if old
        end
        date_settings(item).each do |key|
          old = fixed_date(item, key)
          changes << DateChange.new(key: "#{item.id}.config.#{key}", label: "#{item.label}: #{key.humanize(capitalize: false)}", old: old, proposed: shift(old)) if old
        end
      end
      changes
    end

    # Badges, teams, checklists... named with a year, matched to the name
    # with the year shifted when one exists.
    def replacements
      referenced_records.filter_map do |record|
        name = name_of(record)
        next unless name.to_s.match?(YEAR)

        shifted = name.gsub(YEAR) { |year| (year.to_i + shift_years).to_s }
        Replacement.new(key: key_for(record), record: record, proposed: find_named(record.class, shifted))
      end
    end

    # dates: { key => Date or string } overriding the proposals (blank keeps
    # the old date); replace: { key => id } (blank keeps the record).
    def call(title:, by:, dates: {}, replace: {})
      dates = date_changes.to_h { |change| [ change.key, change.proposed ] }.merge(dates.to_h.transform_values { |value| cast_date(value) }.compact)
      known = replacements.to_h { |replacement| [ replacement.key, replacement.model ] }
      replace = replace.to_h.compact_blank.select { |key, id| known[key]&.exists?(id: id) }

      Checklist.transaction do
        copy = checklist.dup
        copy.assign_attributes(title: title.presence || "#{checklist.title} (copy)", status: :draft, created_by: by,
          computed_at: nil, next_refresh_at: nil)
        %w[starts_on ends_on cutoff_on].each { |field| copy[field] = dates.fetch("checklist.#{field}", copy[field]) }
        copy.save!
        checklist.checklist_organizers.where.not(person_id: by&.id).find_each do |organizer|
          copy.checklist_organizers.create(person_id: organizer.person_id)
        end

        item_ids = {}
        checklist.top_level_items.each { |item| copy_item(item, copy, nil, dates, replace, item_ids) }
        checklist.population_rules.each { |rule| copy_rule(rule, copy, nil, replace) }
        checklist.checklist_grants.each do |grant|
          copy.checklist_grants.create!(badge_id: swap(grant.badge, replace), team_id: swap(grant.team, replace),
            access: grant.access, item_ids: grant.item_ids.filter_map { |id| item_ids[id] })
        end
        copy
      end
    end

    private

    def shift_years
      (shift_months / 12.0).round
    end

    def shift(date)
      date && date + shift_months.months
    end

    def items
      @items ||= checklist.checklist_items.order(:position).to_a
    end

    # Date settings with a fixed date: :date ones, and :relative_date ones
    # set to "on or after <date>" (a "within the last N" stays as it is).
    def date_settings(item)
      Array(item.kind_class&.settings).select { |setting| %i[date relative_date].include?(setting.type) }.map { |setting| setting.key.to_s }
    end

    def fixed_date(item, key)
      value = item.config[key]
      return RelativeDate.from_config(value)&.date if value.is_a?(Hash)

      value.presence && Date.iso8601(value)
    rescue Date::Error
      nil
    end

    def referenced_records
      records = items.flat_map do |item|
        Array(item.kind_class&.references).flat_map { |key, _| item.kind_class.referenced_records(item, key) }
      end
      rules = checklist.checklist_rules.includes(:team, :badge).to_a
      records += rules.flat_map { |rule| [ rule.team, rule.badge ] }
      records += checklist.checklist_grants.includes(:team, :badge).flat_map { |grant| [ grant.team, grant.badge ] }
      records.compact.uniq
    end

    def key_for(record)
      "#{record.class.name}:#{record.id}"
    end

    def name_of(record)
      record.respond_to?(:title) ? record.title : record.try(:name)
    end

    def find_named(model, name)
      column = model.column_names.include?("title") ? :title : :name
      model.find_by(column => name)
    end

    def swap(record, replace)
      return if record.nil?

      replace[key_for(record)].presence || record.id
    end

    def copy_item(item, copy, parent, dates, replace, item_ids)
      new_item = item.dup
      new_item.assign_attributes(checklist: copy, parent: parent, config: copy_config(item, dates, replace))
      %w[starts_on ends_on due_on].each { |field| new_item[field] = dates.fetch("#{item.id}.#{field}", new_item[field]) }
      new_item.save!
      item_ids[item.id] = new_item.id
      item.checklist_rules.each { |rule| copy_rule(rule, copy, new_item, replace) }
      item.children.each { |child| copy_item(child, copy, new_item, dates, replace, item_ids) }
    end

    def copy_config(item, dates, replace)
      config = item.config.deep_dup
      Array(item.kind_class&.references).each do |key, model_name|
        next unless config.key?(key)

        swap_id = ->(id) { replace["#{model_name}:#{id}"].presence || id }
        config[key] = config[key].is_a?(Array) ? config[key].map(&swap_id) : swap_id.call(config[key])
      end
      date_settings(item).each do |key|
        date = dates["#{item.id}.config.#{key}"]
        next unless date && fixed_date(item, key)

        config[key] = config[key].is_a?(Hash) ? RelativeDate.new(date: date).to_config : date.iso8601
      end
      config
    end

    def copy_rule(rule, copy, item, replace)
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
