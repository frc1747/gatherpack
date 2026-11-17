# Stores the status of complete responses whose form's expiry has passed:
# they need re-confirmation, lose the completion badge, and run the
# incomplete hooks, once. Does nothing while forms are turned off, so an
# expiry that passes meanwhile is applied when they're turned back on.
class FormExpiryJob < ApplicationJob
  queue_as :default

  def perform
    FormResponse.past_expiry.includes(:form, :active_submission).find_each(&:sync_status!) if GatherPack::Features.enabled?(:forms)
  end
end
