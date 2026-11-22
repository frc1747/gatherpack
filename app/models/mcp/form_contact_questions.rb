# Which of a form's questions count as a minor's contact details, for every forms
# tool that reads or writes answers. Tools decide who is a minor with
# Mcp.withhold_contact_details?; the reasons behind each check are in
# Mcp::Tools::FormAnswers' class comment.
module Mcp::FormContactQuestions
  WITHHELD_DATA_TYPES = %w[phone email].freeze

  private

  # The given questions without those withheld from a minor: judged as they are now,
  # in this response's snapshots and in the form's history. None of them if the
  # history can't be read, since then no question can be judged.
  def questions_open_for_minor(questions, form, response)
    earlier = earlier_contact_keys(form)
    return [] if earlier.nil?

    answered_as_contact = contact_snapshot_keys(response)
    questions.reject { |question| contact_question?(question) || answered_as_contact.include?(question.key) || earlier.include?(question.key) }
  end

  def contact_question?(question)
    contact?(question.person_field&.system_source, question.value_type.data_type)
  end

  # The keys of questions that counted as contact in any of this response's submissions.
  def contact_snapshot_keys(response)
    response.form_submissions.flat_map { |submission| Array(submission.content["questions"]) }
      .select { |snapshot| contact?(system_sources[snapshot["person_field"]], snapshot["type"]) }
      .map { |snapshot| snapshot["key"] }.to_set
  end

  # The keys of questions on this form with an earlier version that counted as
  # contact, or nil if the history can't be read. Each version's object is the
  # question before that change, and the question as it is now is judged separately.
  # The form's ID is only inside object, the one way to reach a removed question.
  def earlier_contact_keys(form)
    return @earlier_contact_keys if defined?(@earlier_contact_keys)

    @earlier_contact_keys = begin
      states = AuditLog.where(item_type: "FormQuestion").where("object LIKE ?", "%#{form.id}%").pluck(:object)
        .map { |object| PaperTrail.serializer.load(object) }
      raise ArgumentError, "unreadable question version" unless states.all?(Hash)

      states = states.select { |state| state["form_id"] == form.id }
      fields = PersonField.where(id: states.filter_map { |state| state["person_field_id"] }).index_by(&:id)
      states.select { |state| contact_state?(state, fields) }.map { |state| state.fetch("key") }.to_set
    rescue => e
      Rails.logger.error("[MCP] #{self.class.tool_name} can't read question history for form #{form.id} (request #{ctx.request_id}): #{e.class}: #{e.message}")
      nil
    end
  end

  def contact_state?(state, fields)
    field_id = state["person_field_id"]
    return contact?(nil, FormQuestion.data_types.key(state["data_type"]) || state["data_type"]) unless field_id

    field = fields[field_id]
    field.nil? || contact?(field.system_source, field.data_type)
  end

  # Built-in fields by key, archived ones too, for reading snapshots. Built-in
  # fields can't be deleted, and a key missing here is a custom field or none.
  def system_sources
    @system_sources ||= PersonField.system.pluck(:key, :system_source).to_h
  end

  def contact?(source, data_type)
    return true if source && Mcp::MinorRule::WITHHELD_KEYS.include?(source.delete_prefix("user."))

    WITHHELD_DATA_TYPES.include?(data_type)
  end
end
