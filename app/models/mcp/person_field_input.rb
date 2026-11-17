# What set_person_field and update_person_fields share: turning a JSON value into what
# the edit form would send for a field, and the message for a save the required check
# blocked. The Rails log filters for the arguments that carry values are in
# config/initializers/mcp_person_fields.rb.
module Mcp::PersonFieldInput
  REQUIRED_ELSEWHERE = "Another required field is blank; complete it on their profile page.".freeze

  private

  # The save stays blocked by a blank required field, as on the page, but the
  # message can't name a field withheld from this person. The call still fails
  # until that field is filled in, which the viewer, who can write it on the page,
  # could find out there. minor is Mcp.withhold_contact_details?(person) worked out
  # before the new values were assigned: one of them could be the birthday it
  # depends on.
  def save_problem(person, minor)
    if minor
      withheld = person.writable_fields_for(ctx.person).select { |field| Mcp::Tools::GetPersonFields.contact_detail?(field) }.map(&:key)
      return REQUIRED_ELSEWHERE if person.errors.attribute_names.map(&:to_s).intersect?(withheld)
    end

    person.errors.full_messages.to_sentence
  end

  # What the form would send for this value. The form can only send a checkbox,
  # a list of choices, or one line of text, so refuse anything else rather than
  # let the field's conversion guess: "no" would cast to true.
  def form_input(field, value)
    case field.data_type
    when "boolean"
      invalid_argument!("#{field.name} takes true or false") unless [ true, false, nil ].include?(value)
      value ? "1" : "0"
    when "multi_select"
      choices = value.nil? ? [] : Array(value)
      invalid_argument!("#{field.name} takes a list of choices") unless choices.all? { |choice| choice.is_a?(String) && choice.present? }
      choices
    when "integer"
      invalid_argument!("#{field.name} takes a whole number") unless value.nil? || value.is_a?(Integer) || value.is_a?(String)
      value.to_s
    else
      invalid_argument!("#{field.name} takes text") unless value.nil? || value.is_a?(String)
      invalid_argument!("#{field.name} takes one line") if field.data_type != "text" && value.to_s.match?(/[[:cntrl:]]/)
      value.to_s
    end
  end
end
