module Checklists
  # Prepended to ChecklistPolicy::Scope (config/initializers/checklists_count.rb):
  # a checklist holding a wrapped count item is listed to the people the
  # commitment was listed to (CommitmentPolicy::Scope), plus grants: those
  # who run it, and, unless it's a draft, those its count reaches
  # (Checklists::WrappedVisibility) or a grant opens it to. A guardian or
  # leader with nobody to see there doesn't get it listed, unless another
  # item organizers added to it reaches them (its read level and kind, as
  # Checklists::Visibility answers). Other checklists are listed as before.
  #
  # Only the wrapped checklists core already listed, and those the viewer
  # is on the organizer list of (a commitment organizer core doesn't count),
  # are looked at, and each scope resolves once.
  module WrappedChecklistScope
    def resolve
      return @resolved if defined?(@resolved)

      @resolved = narrow_wrapped(super)
    end

    private

    def narrow_wrapped(relation)
      return relation if user.admin? || person.nil?

      wrapped_ids = ::ChecklistItem.where(kind: CountItem::COUNT, wrapped: true).select(:checklist_id)
      listed = relation.where(id: wrapped_ids).ids
      runnable = scope.where(id: wrapped_ids).where(id: ::ChecklistOrganizer.where(person_id: person.id).select(:checklist_id)).where.not(id: listed).to_a
      dropped = scope.where(id: listed).reject { |checklist| wrapped_checklist_shown?(checklist) }.map(&:id)
      added = runnable.select { |checklist| checklist.organizer?(person) }.map(&:id)
      return relation if added.empty? && dropped.empty?

      scope.where(id: relation.where.not(id: dropped).select(:id)).or(scope.where(id: added))
    end

    def wrapped_checklist_shown?(checklist)
      return true if checklist.organizer?(person)
      return false if checklist.draft?
      return true if granted_ids.where(checklist_id: checklist.id).exists?

      items = checklist.checklist_items.to_a
      wrapped = items.find { |item| item.kind == CountItem::COUNT && item.wrapped? }
      results = ::ChecklistResult.where(checklist_id: checklist.id).where.not(item_id: nil).pluck(:item_id, :person_id).group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
      counted = results.fetch(wrapped.id, [])
      # Someone with a result on the count owes it, and sees their own.
      return true if counted.include?(person.id) || Checklists::Kinds::Count.commitment_reach(wrapped, person, counted).any?

      other_item_reaches?(checklist, items - [ wrapped ], results)
    end

    # Whether any other item shows the viewer one of its stored results
    # (Checklists::Visibility: its read level, grants and its kind's cap,
    # Checklists.visible_person_ids).
    def other_item_reaches?(checklist, items, results)
      ids = items.flat_map { |item| results.fetch(item.id, []) }.uniq
      return false if ids.empty?

      visibility = Checklists::Visibility.new(checklist, person).prepare(ids)
      items.any? { |item| results.fetch(item.id, []).any? { |id| visibility.access(item, id) } }
    end
  end
end
