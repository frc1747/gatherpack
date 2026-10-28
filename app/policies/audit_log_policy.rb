class AuditLogPolicy < AdminPolicy
  # Reverting writes the item back, so it takes the rights to make that change
  # directly: the item's own policy has to allow changing the record as it is
  # now (or creating it again, if it's gone) and as it will be. A dynamic
  # page's content runs on the server, so only architects revert a page that
  # is dynamic on either side.
  #
  # A version with nothing to restore (a create) is left to the controller.
  def revert?
    return false unless user&.admin

    reverted = record.reify
    return true if reverted.nil?

    current = record.item
    return false if !user.architect? && [ current, reverted ].any? { |item| item.is_a?(Page) && item.dynamic }

    allowed?(current || reverted, current ? :update? : :create?) && allowed?(reverted, :update?)
  end

  private

  # Join records with no policy of their own keep the admin rule above.
  def allowed?(item, action)
    policy = Pundit.policy(user, item)
    policy.nil? || policy.public_send(action)
  rescue NoMethodError
    # A reified record can miss an association its policy reads (a badge
    # assignment deleted along with its badge), and couldn't be saved anyway.
    false
  end
end
