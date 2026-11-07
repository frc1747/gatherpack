# Included in CommitmentsController and PersonCommitmentsController from
# config/initializers/checklists_count.rb: while checklists are on, the
# commitment pages send people to the checklist screens (checklists spec
# §11.3). The list goes to the checklists, a commitment to its item's
# checklist (its setup to the item's form), and a person's commitments to
# their checklists. A commitment with no item keeps its own pages. The
# source, adjustment and organizer routes stay; the item's form links to
# them.
module CommitmentsToChecklists
  extend ActiveSupport::Concern

  included do
    before_action :redirect_commitments_to_checklists
  end

  private

  def redirect_commitments_to_checklists
    return unless Checklists.enabled?

    if is_a?(PersonCommitmentsController)
      redirect_to person_checklists_path(params[:person_id]), status: :see_other
    elsif action_name == "index"
      redirect_to checklists_path, status: :see_other
    elsif (item = @commitment&.checklist_item) && %w[show edit].include?(action_name)
      path = action_name == "edit" ? edit_checklist_checklist_item_path(item.checklist, item, anchor: "sources") : checklist_path(item.checklist)
      redirect_to path, status: :see_other
    end
  end
end
