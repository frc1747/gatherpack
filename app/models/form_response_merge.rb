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
    if rank(winner) > rank(loser)
      loser.update_columns(active_submission_id: nil)
      loser.form_submissions.destroy_all
      winner.form_submissions.update_all(form_response_id: loser.id)
      loser.update_columns(winner.attributes.slice(*CARRIED))
      winner.update_columns(active_submission_id: nil)
    end
    # The status was worked out for the other person's profile (the merge
    # moves profile values without the forms resync). Sync it once the merge
    # has committed: until then badges and profile values are still moving,
    # and a badge granted now would clash with the one about to move over.
    kept_id = kept["id"]
    ActiveRecord.after_all_transactions_commit { FormResponse.find_by(id: kept_id)&.sync_status! }
  end

  # check for form_responses.subject_id: names the forms both people have
  # a response to. The merge preview runs a check only when some of the
  # merged person's rows move, so if every one of their responses clashes
  # with the kept person's, this warning isn't shown.
  def both_answered(from, to)
    titles = Form.where(id: FormResponse.where(subject_id: from).select(:form_id))
      .where(id: FormResponse.where(subject_id: to).select(:form_id)).order(:title).pluck(:title)
    return if titles.empty?

    "Both people have a response to #{titles.to_sentence}. The more complete one stays; the other is removed."
  end

  def rank(response)
    RANKING.index(response.status) || -1
  end
end
