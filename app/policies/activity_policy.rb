# The activity page for a person (the record): their own, or a current
# ward's. Anyone else, admins included, has the profile; this isn't a
# reporting tool.
class ActivityPolicy < ApplicationPolicy
  def show?
    return false if person.nil? || !record.is_a?(Person)

    record.id == person.id || person.wards.exists?(id: record.id)
  end
end
