module Checklists
  # Prepended to Checklists::Visibility (config/initializers/checklists_count.rb):
  # a wrapped count item, and the overall of the checklist holding one, are
  # seen by exactly the people who saw the commitment before it was wrapped
  # (PersonCommitmentsPolicy): those who run it see everyone; a person sees
  # their own; someone related through the pooling relationship to a member
  # of a person's group (a parent, guardian or not) sees that person. No
  # guardian or leader path is added. Grants still apply. New count items
  # use the read levels of §10.1 instead.
  module WrappedVisibility
    def access(item, person_id)
      # Those who see everything see it either way, with no lookup.
      return super if viewer.nil? || full?

      wrapped = wrapped_count_item(item)
      return super unless wrapped
      return :full if Checklists::Kinds::Count.commitment_reach(wrapped, viewer, @person_ids || [ person_id ]).include?(person_id)

      grant_access(item)
    end

    private

    # The item itself when it's a wrapped count item; for the overall, the
    # checklist's wrapped count item, if it has one.
    def wrapped_count_item(item)
      return (item if item.try(:wrapped?) && item.kind == CountItem::COUNT) if item

      unless defined?(@wrapped_count_item)
        @wrapped_count_item = checklist.checklist_items.find_by(kind: CountItem::COUNT, wrapped: true)
      end
      @wrapped_count_item
    end
  end
end
