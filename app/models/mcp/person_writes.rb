# What create_person and update_person share: the steps of PeopleController's
# create and update that apply to the attributes these tools take.
module Mcp::PersonWrites
  private

  # The form's single-line inputs don't send line breaks or control characters.
  def refuse_control_characters!(attributes)
    bad = attributes.select { |_name, value| value.is_a?(String) && value.match?(/[[:cntrl:]]/) }.keys
    invalid_argument!("#{bad.to_sentence} can't contain line breaks or control characters") if bad.any?
  end

  # Where the build has person fields, the page's create and update run
  # assign_field_values (with nothing to assign here), whose required check blocks
  # the save. The field isn't named: it may be one withheld from this client
  # (Mcp::MinorRule).
  def save_person(person)
    person.assign_field_values({}, acting: ctx.person) if person.respond_to?(:assign_field_values)
    invalid_argument!("A required profile field is blank; complete it on their profile page") unless person.save
  end

  # Audit rows live in their own database, so a rollback has to cover both.
  def in_all_databases(&block)
    AuditLog.transaction { ApplicationRecord.transaction(&block) }
  end
end
