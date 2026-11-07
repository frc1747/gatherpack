# Count items: the Commitments engine as a checklist item kind (checklists
# spec §6.2, §11). Registers the kind, links items to their commitment rows,
# prepends the delegation that lets a linked commitment answer from its item,
# sends the commitment pages to the checklist screens while checklists are
# on, and treats Commitments as on whenever Checklists is, since count items
# need it.

# With checklists on, Commitments counts as on too (its controllers, sign-up
# credit and the rest check Features.enabled?(:commitments)); its own switch
# stays, as the dependency. Defined here, outside reloadable code, so it is
# prepended once.
module ChecklistsTurnOnCommitments
  def enabled?(key)
    super || (key.to_s == "commitments" && super(:checklists))
  end
end
GatherPack::Features.singleton_class.prepend(ChecklistsTurnOnCommitments)

# A credit source's watched notifications (sign-ups, say) mark count items'
# checklists. Subscribed once; the kind decides whether a name is watched.
ActiveSupport::Notifications.subscribe(/\.gatherpack\z/) do |name, *|
  Checklists::Kinds::Count.source_changed(name)
rescue StandardError => e
  Rails.logger.error("Checklists couldn't mark count items after #{name}: #{e.class}: #{e.message}")
end

Rails.application.config.to_prepare do
  next unless defined?(Checklists) && Checklists.respond_to?(:register_item_kind)

  Commitment.has_one :checklist_item, inverse_of: :commitment, dependent: :restrict_with_error
  Commitment.prepend(Checklists::CountCommitment) unless Commitment < Checklists::CountCommitment
  ChecklistItem.include(Checklists::CountItem) unless ChecklistItem < Checklists::CountItem
  Checklists::Refresher.prepend(Checklists::CountPeriods) unless Checklists::Refresher < Checklists::CountPeriods
  Checklists::Visibility.prepend(Checklists::WrappedVisibility) unless Checklists::Visibility < Checklists::WrappedVisibility
  CommitmentAdjustment.include(Checklists::CountAdjustment) unless CommitmentAdjustment < Checklists::CountAdjustment
  Checklists::Kinds::Count::WATCHED.each do |name|
    model = name.constantize
    model.include(Checklists::CountWatched) unless model < Checklists::CountWatched
  end

  Checklists.register_item_kind(:count, Checklists::Kinds::Count)

  CommitmentsController.include(CommitmentsToChecklists) unless CommitmentsController < CommitmentsToChecklists
  PersonCommitmentsController.include(CommitmentsToChecklists) unless PersonCommitmentsController < CommitmentsToChecklists
  ChecklistItemsController.before_action { request.variant = :count if @item&.count? }
  CommitmentSourcesController.include(CountItemCommitmentPages) unless CommitmentSourcesController < CountItemCommitmentPages
  CommitmentAdjustmentsController.include(CountItemCommitmentPages) unless CommitmentAdjustmentsController < CountItemCommitmentPages
end
