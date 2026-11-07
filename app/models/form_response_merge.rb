# When two people merged into one both have a response to the same form,
# the more complete response stays (ties go to the kept person's). The
# merge always removes the response of the person merged away, so when
# that one is more complete its versions, and their signatures, move onto
# the kept response first and the kept response's own are removed.
module FormResponseMerge
  # Least to most complete.
  RANKING = %w[not_started withdrawn draft waiting needs_reconfirmation complete].freeze

  # Copied from the response that wins, with its versions.
  CARRIED = %w[active_submission_id status update_in_progress last_reminded_at].freeze

  module_function

  # on_conflict for form_responses.subject_id: removed and kept are rows of
  # the response being removed and the kept person's response.
  def resolve(removed, kept)
    winner = FormResponse.find(removed["id"])
    loser = FormResponse.find(kept["id"])
    return unless rank(winner) > rank(loser)

    loser.update_columns(active_submission_id: nil)
    loser.form_submissions.destroy_all
    winner.form_submissions.update_all(form_response_id: loser.id)
    loser.update_columns(winner.attributes.slice(*CARRIED))
    winner.update_columns(active_submission_id: nil)
  end

  def rank(response)
    RANKING.index(response.status) || -1
  end
end
