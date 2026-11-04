# Changes a check-in's notes and field answers, as CheckinsController#update and #field_update do.
#
# Mirrors: set_event (line 94), set_checkin (line 85) with CheckinPolicy#update? (the person
# checked in, admins, the managers of the event's team), which #field_update also asks (line 54).
# Notes go through the check-in's own save with created_by set (lines 34-35), so the model's
# validations apply: its check-in limit refuses a full event's edit, as on the page. Answers go
# through the answer's own save (line 55), since a check-in's save would quietly put back one
# the edit form's rule doesn't allow. person_id, which update also permits, isn't taken.
#
# Who may change an answer: the two pages disagree, so this takes the one that allows it. The edit
# form (update) offers a field if permission_check passes and quietly drops it otherwise (_form
# line 8, Checkin#check_attributes). The Arrange page (field_update) offers every field to whoever
# can open it (EventPolicy#arrange?). So a viewer needs either; a field they have neither for is
# refused by name, with nothing changed. A hand-made PATCH to field_update asks neither, and that's
# not copied: no page offers it.
#
# On a build with those rules, CheckinPolicy#show_notes? gates notes and
# CheckinFieldResponsePolicy#update? takes over from the rule above (here that policy has no
# update?, and ApplicationPolicy's allows everyone). A field's read level limits this too, for
# reading and writing, as the build's form does (CheckinField#readable_by?). A field linked to a
# person field holds that person's value, which may be contact details, and stores no answer of its
# own: it's neither returned nor written, which keeps it out of Mcp::MinorRule's way.
class Mcp::Tools::UpdateCheckin < Mcp::Tool
  include Mcp::CheckinRecords

  tool_name "update_checkin"
  description "Change a check-in's notes or field answers, as Edit does on the check-in's page; only what you send changes. " \
    "A check-in you can see but not change is \"Not allowed\", and a field you can't answer is refused by name, with nothing changed. Returns the check-in."
  scope :write
  feature :events
  input_schema(
    properties: {
      checkin_id: { type: "string", description: "The check-in's ID (cki_)" },
      notes: { type: %w[string null], description: "null clears them" },
      field_responses: {
        type: "object",
        description: "Answers by check-in field ID (ckf_); null clears one",
        additionalProperties: { type: %w[string null] }
      }
    },
    required: %w[checkin_id],
    closed: true
  )
  output_schema(
    type: "object",
    properties: Mcp::CheckinRecords::REF_SCHEMA.merge(
      notes: { type: %w[string null] },
      field_responses: {
        type: "array",
        items: {
          type: "object",
          properties: { checkin_field_id: { type: "string" }, name: { type: "string" }, response: { type: %w[string null] } },
          required: %w[checkin_field_id name response]
        }
      }
    ),
    required: %w[id person event notes field_responses]
  )

  def call(checkin_id:, **changes)
    notes = changes.slice(:notes)
    field_responses = changes.fetch(:field_responses, {})
    invalid_argument!("Give notes or field_responses") if notes.empty? && field_responses.empty?

    checkin = find_checkin(checkin_id)
    ctx.authorize!(checkin, :update?)
    ctx.authorize!(checkin, :show_notes?) if notes.any? && ctx.defines?(checkin, :show_notes?)
    refuse_line_breaks!("notes", notes[:notes])
    answers = answers_by_field(checkin, field_responses)

    saved = Checkin.transaction { write(checkin, notes, answers) }
    changed!(*saved) if saved.any?
    checkin_json(checkin)
  end

  private

  # Everything that can refuse, before anything is written: the versions database isn't part of
  # the transaction below, so a rollback wouldn't take back an audit row.
  def answers_by_field(checkin, field_responses)
    fields = checkin.event.event_type.checkin_fields
    answers = field_responses.to_h { |field_id, answer| [ ctx.find(fields, field_id), answer ] }
    answers.each { |field, answer| refuse_line_breaks!(field.name, answer) }
    refused = answers.keys.reject { |field| may_answer?(checkin, field) }
    raise Mcp::NotAllowed, "Not allowed: #{refused.map(&:name).to_sentence}" if refused.any?

    answers
  end

  def may_answer?(checkin, field)
    return false if field.try(:linked?) || !readable?(checkin, field)

    answer = checkin.checkin_field_responses.detect { |response| response.checkin_field_id == field.id } ||
      CheckinFieldResponse.new(checkin: checkin, checkin_field: field)
    return ctx.allowed?(answer, :update?) if ctx.defines?(answer, :update?)

    answer.permission_check(ctx.person) || ctx.allowed?(checkin.event, :arrange?)
  end

  def readable?(checkin, field)
    !field.respond_to?(:readable_by?) || field.readable_by?(ctx.person, checkin.person)
  end

  # The records whose values changed, the check-in first.
  def write(checkin, notes, answers)
    checkin.refresh_fields
    saved = []
    if notes.any?
      checkin.created_by = ctx.person
      invalid_argument!(checkin.errors.full_messages.to_sentence) unless checkin.update(notes)
      saved << checkin if checkin.saved_changes?
    end
    answers.each do |field, answer|
      response = checkin.checkin_field_responses.detect { |row| row.checkin_field_id == field.id }
      invalid_argument!(response.errors.full_messages.to_sentence) unless response.update(response: answer)
      saved << response if response.saved_changes?
    end
    saved
  end

  def checkin_json(checkin)
    answers = checkin.checkin_field_responses.index_by(&:checkin_field_id)
    fields = checkin.event.event_type.checkin_fields.order(:name, :id).reject { |field| field.try(:linked?) || !readable?(checkin, field) }
    checkin_ref_json(checkin).merge(
      notes: !ctx.defines?(checkin, :show_notes?) || ctx.allowed?(checkin, :show_notes?) ? checkin.notes : nil,
      field_responses: fields.map { |field| { checkin_field_id: field.neat_id, name: field.name, response: answers[field.id]&.response } }
    )
  end

  # The edit form's notes and answers are single-line inputs.
  def refuse_line_breaks!(name, value)
    invalid_argument!("#{name} can't contain line breaks or control characters") if value&.match?(Mcp::PunchRecords::SINGLE_LINE_REFUSED)
  end
end
