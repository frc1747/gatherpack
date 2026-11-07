module Checklists
  # check callables for merging two people into one (GatherPack::PersonMerge):
  # a warning for the merge preview, or nil.
  module MergeChecks
    module_function

    # Rules naming each person move as they are, so a checklist that names
    # both ends up with two rules for the kept person, which may disagree.
    def rules(from, to)
      shared = ChecklistRule.where(person_id: from)
        .where(checklist_id: ChecklistRule.where(person_id: to).select(:checklist_id))
        .distinct.count(:checklist_id)
      return if shared.zero?

      "Both people are named in the rules of #{shared} #{"checklist".pluralize(shared)}. Check who they cover after the merge."
    end
  end
end
