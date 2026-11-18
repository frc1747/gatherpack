module Checklists
  module Kinds
    # Age in a range on a date: the item's end date by default (or today when
    # it runs to now), or a chosen date. Shows pass or fail, never the
    # birthday.
    class Age < ItemKind
      class << self
        def label = "Age"
        def description = "Is old or young enough"
        def uses_dates? = true

        def settings
          [
            ItemKind::Setting.new(key: :min, type: :number, label: "At least"),
            ItemKind::Setting.new(key: :max, type: :number, label: "At most"),
            ItemKind::Setting.new(key: :on, type: :date, label: "On", hint: "Blank: the item's end date, or today")
          ]
        end

        def invalidations
          [ [ ::Person, ->(person) { [ person.id ] } ] ]
        end

        def validate(item)
          min, max = item.config.values_at("min", "max")
          item.errors.add(:base, "Give a minimum or a maximum age") if min.blank? && max.blank?
          item.errors.add(:base, "The minimum age is above the maximum") if min.present? && max.present? && min.to_i > max.to_i
        end

        # Ages measured on "today" change at midnight.
        def next_change_at(item, context)
          return if item.config["on"].present? || context.window_for(item).ends_on

          context.as_of.to_date.tomorrow.in_time_zone.beginning_of_day
        end

        def describe(item)
          min, max = item.config.values_at("min", "max")
          range = if min.present? && max.present? then "#{min} to #{max}"
          elsif min.present? then "#{min} or older"
          else "#{max} or younger"
          end
          "Aged #{range}"
        end
      end

      def evaluate(person_ids)
        birthdays = ::Person.where(id: person_ids).pluck(:id, :birthday).to_h
        on = config["on"].present? ? Date.parse(config["on"]) : (window.ends_on || context.as_of.to_date)
        sentence = self.class.describe(item)

        person_ids.index_with do |person_id|
          birthday = birthdays[person_id]
          next Result.not_met("No birthday on file", fix: { "label" => "Add a birthday", "by" => "person" }) if birthday.nil?

          age = age_on(birthday, on)
          in_range = (config["min"].blank? || age >= config["min"].to_i) && (config["max"].blank? || age <= config["max"].to_i)
          in_range ? Result.met(sentence) : Result.not_met("Not #{sentence.downcase_first}")
        end
      end

      private

      def age_on(birthday, date)
        date.year - birthday.year - (date.month > birthday.month || (date.month == birthday.month && date.day >= birthday.day) ? 0 : 1)
      end
    end
  end
end
