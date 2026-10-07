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
end
