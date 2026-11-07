module Checklists
  module Kinds
    # A person's value for a profile field passes a test. The tests offered
    # depend on the field's data type; a blank value counts as met or not yet
    # as the item says (default not yet). Results say whether the test passed,
    # never what the value is.
    class PersonField < ItemKind
      OPERATORS = {
        "any_of" => "is any of",
        "none_of" => "is none of",
        "yes" => "is yes",
        "no" => "is no",
        "on_or_after" => "is on or after",
        "on_or_before" => "is on or before",
        "at_least" => "is at least",
        "at_most" => "is at most",
        "filled_in" => "is filled in"
      }.freeze

      OPERATORS_BY_TYPE = {
        "string" => %w[ any_of none_of filled_in ],
        "text" => %w[ any_of none_of filled_in ],
        "phone" => %w[ any_of none_of filled_in ],
        "email" => %w[ any_of none_of filled_in ],
        "select" => %w[ any_of none_of filled_in ],
        "multi_select" => %w[ any_of none_of filled_in ],
        "boolean" => %w[ yes no filled_in ],
        "date" => %w[ on_or_after on_or_before filled_in ],
        "integer" => %w[ at_least at_most filled_in ]
      }.freeze

      class << self
        # Who acts on "Update <field>" (Result "by"), from who may write the
        # field: "guardian" when a guardian may (with the person, at family
        # and team), "person" when only the person and leaders may, else
        # "leader". A field the person can only read isn't theirs to update.
        def updated_by(field)
          return "person" if field.write_permission == "everyone"

          parts = AudienceLevels.components(field.write_permission)
          if parts.include?(:guardian) then "guardian"
          elsif parts.include?(:subject) && !field.system_read_only? then "person"
          else "leader"
          end
        end

        def label = "Profile field"
        def description = "Has a profile field filled in a certain way"

        def settings
          settings_for(nil)
        end

        # The form as offered to an author: only fields they can read for
        # someone (all of them for an admin, or when no author is given),
        # and always the item's saved field, so renaming an item never
        # points it elsewhere.
        def settings_for(author, item = nil)
          [
            ItemKind::Setting.new(key: :field_id, type: :choice, label: "Field", options: field_options(author, item)),
            ItemKind::Setting.new(key: :operator, type: :choice, label: "Test", options: OPERATORS.invert.to_a,
              hint: "Which tests fit depends on the field: choices and text use \"is any of\" or \"is none of\", yes/no fields \"is yes\" or \"is no\", dates \"on or after\" or \"on or before\", numbers \"at least\" or \"at most\""),
            ItemKind::Setting.new(key: :values, type: :text, label: "Values", hint: "For \"is any of\" and \"is none of\": one or more, separated by commas"),
            ItemKind::Setting.new(key: :date, type: :relative_date, label: "Date", hint: "For the date tests. \"Within the last\" counts back from today"),
            ItemKind::Setting.new(key: :number, type: :number, label: "Number", hint: "For the number tests"),
            ItemKind::Setting.new(key: :blank, type: :choice, label: "If it's blank", options: [ [ "Not yet", "not_met" ], [ "Counts as met", "met" ] ]),
            ItemKind::Setting.new(key: :changed_since, type: :relative_date, label: "Last changed", hint: "Optional. A value not updated since then doesn't count")
          ]
        end

        def references = { "field_id" => "PersonField" }

        def invalidations
          [
            [ ::PersonFieldValue, ->(value) { [ value.person_id ] } ],
            [ ::Person, ->(person) { [ person.id ] } ],
            [ ::User, ->(user) { [ user.person&.id ] } ]
          ]
        end

        def field(item)
          ::PersonField.find_by(id: item.config["field_id"]) if item.config["field_id"].present?
        end

        def problems(item)
          problems = missing_references(item)
          field = field(item)
          if item.config["field_id"].blank?
            problems << "No field chosen"
          elsif field&.archived?
            problems << "#{field.name} is archived"
          end
          problems << "\"#{OPERATORS[item.config["operator"]]}\" doesn't fit #{field.name}" if field && !operator_fits?(field, item.config["operator"])
          problems << unusable_reason(item, field) if field && unusable_reason(item, field)
          problems.concat(unknown_choices(item, field).map { |value| "\"#{value}\" isn't one of #{field.name}'s choices" }) if field
          problems
        end

        # Why the item can't be tested at all, or nil.
        def unusable_reason(item, field)
          if !field.system? && !GatherPack::Features.enabled?(:person_fields)
            "Profile fields are switched off"
          elsif field.system? && item.config["changed_since"].present?
            "\"Last changed\" can't be checked on a built-in field"
          end
        end

        # The typed values that aren't among a choice field's choices.
        def unknown_choices(item, field)
          return [] unless field.type_select? || field.type_multi_select?
          return [] unless %w[ any_of none_of ].include?(item.config["operator"])

          choices = field.choice_list.map(&:downcase)
          values(item).reject { |value| choices.include?(value.downcase) }
        end

        def validate(item)
          field = field(item)
          return item.errors.add(:base, "Choose a field") if field.nil?

          operator = item.config["operator"]
          return item.errors.add(:base, "\"#{OPERATORS[operator] || "That test"}\" doesn't fit #{field.name}") unless operator_fits?(field, operator)

          reason = unusable_reason(item, field)
          item.errors.add(:base, reason) if reason && field.system?
          unknown_choices(item, field).each { |value| item.errors.add(:base, "\"#{value}\" isn't one of #{field.name}'s choices") }
          item.errors.add(:base, "Give at least one value") if %w[ any_of none_of ].include?(operator) && values(item).empty?
          item.errors.add(:base, "Choose a date") if %w[ on_or_after on_or_before ].include?(operator) && relative(item, "date").nil?
          item.errors.add(:base, "Give a number") if %w[ at_least at_most ].include?(operator) && item.config["number"].blank?
        end

        def describe(item)
          field = field(item)
          return "A profile field that no longer exists" unless field

          operator = item.config["operator"]
          sentence = case operator
          when "any_of", "none_of" then "#{field.name} #{OPERATORS[operator]} #{values(item).to_sentence(two_words_connector: " or ", last_word_connector: ", or ")}"
          when "on_or_after", "on_or_before" then "#{field.name} #{date_phrase(operator, relative(item, "date"))}".strip
          when "at_least", "at_most" then "#{field.name} #{OPERATORS[operator]} #{item.config["number"]}"
          else "#{field.name} #{OPERATORS[operator]}"
          end
          changed = relative(item, "changed_since")
          changed ? "#{sentence}, changed #{changed.relative? ? changed.describe : "since #{I18n.l(changed.date, format: :long)}"}" : sentence
        end

        # A stored relative date setting, or nil.
        def relative(item, key)
          RelativeDate.from_config(item.config[key])
        end

        # The date tests read plainly for both kinds of date.
        def date_phrase(operator, date)
          return OPERATORS[operator] if date.nil?

          if date.relative?
            operator == "on_or_after" ? "is #{date.describe}" : "is at least #{date.amount} #{date.amount == 1 ? date.unit.singularize : date.unit} ago"
          else
            "#{OPERATORS[operator]} #{I18n.l(date.date, format: :long)}"
          end
        end

        # Relative dates move at midnight.
        def next_change_at(item, context)
          dates = []
          dates << relative(item, "date") if %w[ on_or_after on_or_before ].include?(item.config["operator"])
          dates << relative(item, "changed_since")
          dates.compact.filter_map { |date| date.next_change_at(context.as_of) }.min
        end

        # Reading a field's value can't show anyone more than the field does:
        # a person's result is hidden from a viewer who can't read the field
        # for that person (its audience, badge grants and team), whoever the
        # viewer is.
        def visible_to?(item, viewer, person)
          field = field(item)
          field.nil? || field.readable_by?(viewer, person)
        end

        def visible_person_ids(item, viewer, person_ids)
          field = field(item)
          return person_ids if field.nil?

          readable = field.readable_subjects_for(viewer).where(id: person_ids).pluck(:id).to_set
          person_ids.select { |id| readable.include?(id) }
        end

        # Nobody sets up a test on a field they couldn't read for everyone
        # the checklist covers.
        def authorable_by?(item, author)
          field = field(item)
          return true if field.nil? || item.checklist.nil?

          covered = Checklists::Evaluator.new(item.checklist).covered_ids
          (covered - visible_person_ids(item, author, covered)).empty?
        end

        def values(item)
          item.config["values"].to_s.split(",").map(&:strip).compact_blank
        end

        def operator_fits?(field, operator)
          OPERATORS_BY_TYPE.fetch(field.data_type, []).include?(operator)
        end

        private

        def field_options(author, item)
          fields = ::PersonField.in_use.ordered
          saved = item&.config&.dig("field_id")
          fields = fields.select { |field| field.id == saved || field.readable_subjects_for(author).exists? } if author && !author.admin?
          fields.map { |field| [ field.name, field.id ] }
        end
      end

      def evaluate(person_ids)
        field = self.class.field(item)
        sentence = self.class.describe(item)
        return person_ids.index_with { Result.not_met("Its field was deleted", detail: "The profile field this item tests was deleted") } if field.nil?
        return person_ids.index_with { Result.not_met("Can't be checked", detail: "#{sentence} can't be tested: the test doesn't fit the field") } unless self.class.operator_fits?(field, config["operator"])

        reason = self.class.unusable_reason(item, field)
        return person_ids.index_with { Result.not_met(reason, detail: "#{sentence} can't be tested: #{reason.downcase_first}") } if reason

        stored = load_values(field, person_ids)
        person_ids.index_with { |person_id| judge(field, sentence, *stored.fetch(person_id, [ nil, nil ])) }
      end

      private

      # { person_id => [raw value or nil, when it last changed] }
      def load_values(field, person_ids)
        if field.system?
          rows = ::Person.where(id: person_ids).includes(:user).to_a
          rows.to_h { |person| [ person.id, [ field.system_value(person), person.updated_at ] ] }
        else
          ::PersonFieldValue.where(person_field_id: field.id, person_id: person_ids).pluck(:person_id, :value, :updated_at)
            .to_h { |person_id, value, updated_at| [ person_id, [ value.nil? ? nil : field.cast(value), updated_at ] ] }
        end
      end

      def judge(field, sentence, value, changed_at)
        return judge_blank(field, sentence) if blank?(value)
        return Result.met(sentence) if config["operator"] == "filled_in" && stale_value(changed_at).nil?
        return Result.not_met("Not changed since #{since}", detail: "#{field.name} hasn't been updated since #{since}", fix: fix(field)) if stale_value(changed_at)

        passes?(field, value) ? Result.met(sentence) : Result.not_met("Not: #{sentence.downcase_first}", fix: fix(field))
      end

      def judge_blank(field, sentence)
        if config["blank"] == "met" && config["operator"] != "filled_in"
          Result.met(sentence, detail: "#{field.name} is blank, which this item counts as met")
        else
          Result.not_met("No #{field.name.downcase_first} on file", detail: "#{field.name} is blank", fix: fix(field))
        end
      end

      def blank?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end

      def stale_value(changed_at)
        since = relative_date(:changed_since)&.resolve(context.as_of)
        since.present? && changed_at < since.in_time_zone.beginning_of_day
      end

      def since
        I18n.l(relative_date(:changed_since).resolve(context.as_of), format: :long)
      end

      def passes?(field, value)
        case config["operator"]
        when "any_of" then (Array(value).map(&:to_s).map(&:downcase) & wanted).any?
        when "none_of" then (Array(value).map(&:to_s).map(&:downcase) & wanted).empty?
        when "yes" then value == true
        when "no" then value == false
        when "on_or_after" then value >= relative_date(:date).resolve(context.as_of)
        when "on_or_before" then value <= relative_date(:date).resolve(context.as_of)
        when "at_least" then value.to_i >= config["number"].to_i
        when "at_most" then value.to_i <= config["number"].to_i
        else true
        end
      end

      def wanted
        @wanted ||= self.class.values(item).map(&:downcase)
      end

      def fix(field)
        { "label" => "Update #{field.name.downcase_first}", "by" => self.class.updated_by(field) }
      end
    end
  end
end
