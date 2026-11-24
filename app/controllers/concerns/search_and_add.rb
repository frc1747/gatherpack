# Backs the "search and add" panel (app/views/shared/_add_panel.html.erb): a
# search box listing records that can be added, each with an Add button that
# updates the page in place.
module SearchAndAdd
  extend ActiveSupport::Concern

  CANDIDATE_LIMIT = 25

  private

  # Turbo advertises stream support on every form submission, so only answer
  # with a stream when the panel asked for one in the URL. Ordinary forms keep
  # their redirects.
  def inline_request?
    params[:format] == "turbo_stream"
  end

  def load_candidates(scope, search_predicate)
    candidates = scope
      .ransack(search_predicate => params[:candidate_q])
      .result(distinct: true)
      .limit(CANDIDATE_LIMIT + 1)
      .to_a
    @more_candidates = candidates.size > CANDIDATE_LIMIT
    @candidates = candidates.first(CANDIDATE_LIMIT)
  end
end
