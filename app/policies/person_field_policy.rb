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

  # Anyone who can read at least one field for someone.
  def roster?
    return true if user&.admin
    readable_fields.any?
  end

  def readable_fields
    @readable_fields ||= PersonField.in_use.ordered.includes(person_field_badge_grants: :badge)
      .select { |field| field.readable_subjects_for(person).exists? }
  end
end
