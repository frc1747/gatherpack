module Checklists
  # Included in CommitmentAdjustment (config/initializers/checklists_count.rb):
  # on a count item's commitment, the error for someone who doesn't owe names
  # the item, since people never see the word "commitment".
  module CountAdjustment
    extend ActiveSupport::Concern

    NOT_OWING = "doesn't owe this commitment".freeze

    included do
      after_validation :name_count_item_in_errors
    end

    private

    def name_count_item_in_errors
      return unless errors.added?(:person, NOT_OWING)
      return unless Checklists.enabled? && (item = commitment&.checklist_item)

      errors.delete(:person, NOT_OWING)
      errors.add(:person, "doesn't owe #{item.label}")
    end
  end
end
