module Checklists
  # Keeps stored results right by change (spec §8.2). Each kind lists
  # invalidations, [Model, ->(record) { person ids or :all }]; registering
  # the kind includes Invalidation::Watched in those models, whose
  # after_commit marks the people of every checklist using the kind (see
  # Checklists.mark). Population changes (memberships, badges, applications,
  # teams, a deleted person) mark every checklist. With the feature off
  # nothing happens.
  module Invalidation
    POPULATION = {
      "Membership" => ->(record) { [ record.person_id ] },
      "BadgeAssignment" => ->(record) { [ record.person_id ] },
      "MembershipApplication" => ->(record) { [ record.person_id ] },
      "Team" => ->(_record) { :all },
      # A deleted person leaves rules naming them with no target.
      "Person" => ->(record) { record.destroyed? ? :all : [] }
    }.freeze

    module Watched
      extend ActiveSupport::Concern

      included do
        after_commit :mark_checklists_for_refresh
      end

      private

      def mark_checklists_for_refresh
        return unless Checklists.enabled?

        Checklists::Invalidation.changed(self)
      rescue StandardError => e
        Rails.logger.error("Checklists couldn't mark results after a #{self.class.name} change: #{e.class}: #{e.message}")
      end
    end

    class << self
      def install(kind)
        kind.invalidations.each { |model, _| watch(model) }
      end

      def install_population
        POPULATION.each_key { |name| watch(name.constantize) }
      end

      def watch(model)
        model.include(Watched) unless model < Watched
      end

      def changed(record)
        name = record.class.name
        if (population = POPULATION[name])
          people = population.call(record)
          Checklists.mark(Checklist.refreshable.to_a, people) if people == :all || people.any?
        end

        Checklists.item_kinds.each do |kind_name, kind|
          kind.invalidations.each do |model, people|
            next unless record.is_a?(model)

            checklists = Checklist.refreshable.where(id: ChecklistItem.where(kind: kind_name).select(:checklist_id)).to_a
            Checklists.mark(checklists, people.call(record))
          end
        end
      end
    end
  end
end
