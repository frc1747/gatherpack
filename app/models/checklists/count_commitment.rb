module Checklists
  # Prepended to Commitment (config/initializers/checklists_count.rb) so a
  # commitment that belongs to a count item answers its population, organizer
  # and period questions from the item (checklists spec §11.2):
  #
  #   owing_people        the checklist's population narrowed by the item's rules
  #   organizer?          the checklist's organizer check
  #   organizer_candidate?
  #   period_times        the item's resolved dates, ended at the checklist's cutoff
  #   team_and_below_ids  the checklist's team and below
  #
  # A commitment with no item, or any commitment while checklists are off,
  # uses its own columns. Progress, groups, sources and adjustments are
  # untouched, so every caller of the commitments API keeps working.
  #
  # The count kind evaluates with a commitment it set up itself (draft
  # settings, the evaluator's population and as-of moment): see
  # Checklists::Kinds::Count.commitment_for.
  module CountCommitment
    attr_writer :count_item, :count_person_ids, :count_as_of

    # The item this commitment answers to, or nil.
    def count_item
      return @count_item if @count_item

      checklist_item if Checklists.enabled?
    end

    def owing_people
      item = count_item
      return super unless item

      Person.where(id: @count_person_ids || Checklists::Kinds::Count.owing_ids(item))
    end

    def organizer?(person)
      item = count_item
      return super unless item

      item.checklist.organizer?(person)
    end

    def organizer_candidate?(person)
      item = count_item
      return super unless item

      item.checklist.organizer_candidate?(person)
    end

    def period_times
      item = count_item
      return super unless item

      Checklists::Kinds::Count.period_for(item, as_of: @count_as_of)
    end

    def team_and_below_ids
      item = count_item
      return super unless item

      Checklists.team_subtree_ids(item.checklist.team_id)
    end
  end
end
