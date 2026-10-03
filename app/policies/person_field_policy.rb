class PersonFieldPolicy < AdminPolicy
  def move?
    update?
  end

  def archive?
    update?
  end

  def restore?
    update?
  end

  def destroy?
    user&.admin && record.destroyable?
  end

  def preview?
    user&.admin
  end

  def apply_recommended?
    user&.admin
  end

  # Open to everyone; the page only lists fields the user can read for
  # someone, and says so when there are none.
  def roster?
    true
  end

  # Fields the user can read for at least one person.
  def readable_fields
    @readable_fields ||= PersonField.in_use.ordered.includes(person_field_badge_grants: :badge)
      .select { |field| field.readable_subjects_for(person).exists? }
  end
end
