module Checklists
  module Kinds
    class Attendance < ItemKind
      # Copying a checklist shifts each attendance rule's fixed dates with
      # the rest (spec §9.3): a start "on or after <date>" and an end. A
      # "within the last N" start stays as it is. Prepended to
      # Checklists::Copier by config/initializers/checklists_attendance.rb,
      # since the copier only knows dates that are settings.
      module CopiesRuleDates
        def date_changes
          super + items.select { |item| item.kind_class == Attendance }.flat_map do |item|
            Attendance.rules(item).flat_map do |rule|
              starts = rule.starts unless rule.starts&.relative?
              [ [ "starts", "from", starts&.date ], [ "ends_on", "until", rule.ends_on ] ].filter_map do |field, word, old|
                next unless old

                Copier::DateChange.new(key: "#{item.id}.config.rules.#{rule.index}.#{field}", label: "#{item.label}: #{rule.name} #{word}",
                  old: old, proposed: shift(old))
              end
            end
          end
        end

        private

        def copy_config(item, dates, replace)
          config = super
          return config unless item.kind_class == Attendance

          config["rules"] = Array(config["rules"]).each_with_index.map do |row, index|
            row = row.dup
            starts = RelativeDate.from_config(row["starts"])
            if starts && !starts.relative? && (date = dates["#{item.id}.config.rules.#{index}.starts"])
              row["starts"] = RelativeDate.new(date: date).to_config
            end
            if row["ends_on"].present? && (date = dates["#{item.id}.config.rules.#{index}.ends_on"])
              row["ends_on"] = date.iso8601
            end
            row
          end
          config
        end
      end
    end
  end
end
