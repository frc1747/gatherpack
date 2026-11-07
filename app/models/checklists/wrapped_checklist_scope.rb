module Checklists
  # Prepended to ChecklistPolicy::Scope (config/initializers/checklists_count.rb):
  # a checklist holding a wrapped count item is listed to exactly the people
  # the commitment was listed to (CommitmentPolicy::Scope), plus grants:
  # those who run it, and, unless it's a draft, those its count reaches
  # (Checklists::WrappedVisibility) or a grant opens it to. A guardian or
  # leader with nobody to see there doesn't get it listed. Other checklists
  # are listed as before.
  module WrappedChecklistScope
    def resolve
      relation = super
      return relation if user.admin? || person.nil?

      wrapped = scope.where(id: ::ChecklistItem.where(kind: CountItem::COUNT, wrapped: true).select(:checklist_id)).to_a
      return relation if wrapped.empty?

      listed = relation.where(id: wrapped.map(&:id)).ids
      shown, hidden = wrapped.partition { |checklist| wrapped_checklist_shown?(checklist) }
      added = shown.map(&:id) - listed
      dropped = hidden.map(&:id) & listed
      return relation if added.empty? && dropped.empty?

      scope.where(id: relation.where.not(id: dropped).select(:id)).or(scope.where(id: added))
    end

    private

    def wrapped_checklist_shown?(checklist)
      return true if checklist.organizer?(person)
      return false if checklist.draft?
      return true if granted_ids.where(checklist_id: checklist.id).exists?

      item = checklist.checklist_items.find_by(kind: CountItem::COUNT, wrapped: true)
      ids = ::ChecklistResult.where(item_id: item.id).pluck(:person_id)
      Checklists::Kinds::Count.commitment_reach(item, person, ids).any?
    end
  end
end
