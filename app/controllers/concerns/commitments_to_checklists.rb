# Included in CommitmentsController and PersonCommitmentsController from
# config/initializers/checklists_count.rb: while checklists are on, the
# commitment pages send people to the checklist screens (checklists spec
# §11.3). The list goes to the checklists, a commitment to its item's
# checklist (its setup to the item's form), and a person's commitments to
# their checklists (or the checklists list, for a viewer who can't open the
# person's page). A commitment with no item keeps its own pages. The
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
      redirect_to person_checklists_redirect, status: :see_other
    elsif action_name == "index"
      redirect_to checklists_path, status: :see_other
    elsif (item = @commitment&.checklist_item) && %w[show edit].include?(action_name)
      path = action_name == "edit" ? edit_checklist_checklist_item_path(item.checklist, item, anchor: "sources") : checklist_path(item.checklist)
      redirect_to path, status: :see_other
    end
  end

  # The person's checklists for viewers who may open the person's page;
  # others (a pooled relative who isn't a guardian) get the checklists list,
  # which holds the checklists they may see for the person.
  def person_checklists_redirect
    person = Person.find(params[:person_id])
    policy_scope(Person).exists?(id: person.id) ? person_checklists_path(person) : checklists_path
  rescue ActiveRecord::RecordNotFound
    checklists_path
  end
end
