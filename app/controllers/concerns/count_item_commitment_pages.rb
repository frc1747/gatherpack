# Included in CommitmentSourcesController and CommitmentAdjustmentsController
# from config/initializers/checklists_count.rb. While checklists are on, the
# pages for a count item's sources and credit are the item's: they render
# the "count" variant (the item in the breadcrumb, Cancel back to its form),
# and the controllers send people back to the item's form rather than to the
# commitment.
module CountItemCommitmentPages
  extend ActiveSupport::Concern

  included do
    before_action :use_count_item_pages
    helper_method :count_item
  end

  private

  def count_item
    return @count_item if defined?(@count_item)

    @count_item = (@commitment&.checklist_item if Checklists.enabled?)
  end

  def use_count_item_pages
    request.variant = :count if count_item
  end

  def redirect_to(options = {}, response_options = {})
    super(count_item ? count_item_return(options) : options, response_options)
  end

  # The commitment or its setup page, swapped for the item's form at the
  # part this page manages.
  def count_item_return(options)
    anchor = is_a?(CommitmentAdjustmentsController) ? "adjustments" : "sources"
    to_commitment = options == @commitment ||
      (options.is_a?(String) && URI.parse(options).path.in?([ commitment_path(@commitment), edit_commitment_path(@commitment) ]))
    to_commitment ? edit_checklist_checklist_item_path(count_item.checklist, count_item, anchor: anchor) : options
  rescue URI::InvalidURIError
    options
  end
end
