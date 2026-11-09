# Whether a viewer may follow a form item's fix link for one person: fill
# in or update their response, or sign it. Asks FormResponsePolicy, as the
# form pages themselves do.
class Checklists::FormResponseSlotPolicy < ApplicationPolicy
  def edit?
    response_policy.edit?
  end

  def sign?
    response_policy.sign?
  end

  private

  def response_policy
    @response_policy ||= FormResponsePolicy.new(user, record.response)
  end
end
