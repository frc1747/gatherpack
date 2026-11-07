# Passed to "person_fields - value changed" hooks, once per changed field.
class PersonFieldChange
  attr_reader :person, :field, :old_value, :new_value, :changed_by

  def initialize(person:, field:, old_value:, new_value:, changed_by:)
    @person = person
    @field = field
    @old_value = old_value
    @new_value = new_value
    @changed_by = changed_by
  end

  def key
    field.key
  end
end
