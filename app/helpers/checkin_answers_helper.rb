module CheckinAnswersHelper
  # The Delete confirmation for a check-in field or event type, saying how
  # many check-in answers go with it.
  def checkin_answers_delete_confirm(answer_count)
    return "Are you sure?" if answer_count.zero?

    "Are you sure? This also deletes #{pluralize(answer_count, "check-in answer")}."
  end
end
