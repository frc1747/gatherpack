module CheckinAnswersHelper
  # What the Delete confirmation calls the record, by the page it's on.
  CHECKIN_ANSWERS_DELETE_NOUNS = { "event_types" => "event type", "checkin_fields" => "check-in field" }.freeze

  # The Delete confirmation for a check-in field or event type, saying the
  # effect: the record and how many check-in answers go with it.
  def checkin_answers_delete_confirm(answer_count)
    noun = CHECKIN_ANSWERS_DELETE_NOUNS.fetch(controller_name, "item")
    return "Delete this #{noun}?" if answer_count.zero?

    "Delete this #{noun} and its #{pluralize(answer_count, "check-in answer")}?"
  end
end
