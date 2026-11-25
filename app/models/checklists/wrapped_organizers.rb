module Checklists
  # Prepended to Checklist (config/initializers/checklists_count.rb): a
  # checklist holding a wrapped count item is also run by whoever could run
  # the commitment it wraps. An organizer on its list counts while their
  # commitments_organizers badge still reaches its team, as on the
  # commitment, even once checklists_organizers names a different badge;
  # holders of that badge may be added as organizers. Other checklists use
  # checklists_organizers alone.
  module WrappedOrganizers
    def organizer?(person)
      super || wrapped_commitment_organizer?(person)
    end

    def organizer_candidate?(person)
      super || (wrapped_count? && Commitment.organizer_team_ids(person).include?(team_id))
    end

    # Whether one of the checklist's items is a wrapped commitment.
    def wrapped_count?
      checklist_items.exists?(kind: CountItem::COUNT, wrapped: true)
    end

    private

    def wrapped_commitment_organizer?(person)
      return false if person.nil? || !checklist_organizers.exists?(person_id: person.id)

      wrapped_count? && Commitment.creatable_team_ids(person).include?(team_id)
    end
  end
end
