module Housekeeping
  # The person field answers the "medical and emergency answers" purge
  # clears: answers to the fields named in housekeeping_purge_fields (field
  # names or field group names, one per line) of people with no activity
  # since the cutoff. The person and the rest of their record stay.
  module FieldAnswers
    class << self
      def field_ids
        names = Settings[:housekeeping_purge_fields].to_s.lines.map { |line| line.strip.downcase }.compact_blank
        return [] if names.empty?

        groups = PersonFieldGroup.where("LOWER(name) IN (?)", names).select(:id)
        PersonField.where("LOWER(name) IN (?)", names).or(PersonField.where(person_field_group_id: groups)).ids
      end

      def records(cutoff)
        ids = field_ids
        return PersonFieldValue.none if ids.empty?

        PersonFieldValue.where(person_field_id: ids, person_id: Housekeeping.people_without_activity_since(cutoff).select(:id))
          .where.not(value: [ nil, "" ])
      end

      def people_count(records)
        records.distinct.count(:person_id)
      end

      def summary(records)
        answers = records.count
        people = people_count(records)
        "#{answers} #{"answer".pluralize(answers)} from #{people} #{people == 1 ? "person" : "people"}"
      end

      # One line per person: which answers go (never the answers themselves).
      def describe(records)
        records.includes(:person, :person_field).group_by(&:person).sort_by { |person, _| person.display_name.to_s }.map do |person, values|
          [ person.display_name, values.map { |value| value.person_field.name }.sort.to_sentence ]
        end
      end
    end
  end
end
