module Signups
  # Included into Checkin from config/initializers/signups.rb (decision 7),
  # so checkin.rb stays as upstream has it. A check-in means the person
  # showed up: their active sign-ups to people positions at the event become
  # fulfilled. It never creates a sign-up, and item sign-ups are marked by an
  # organizer (bringing food doesn't mean staying).
  module CheckinFulfilment
    extend ActiveSupport::Concern

    included do
      after_create_commit :fulfil_signups_for_checkin
    end

    private

    def fulfil_signups_for_checkin
      Signup.fulfil_for_checkin!(self) if GatherPack::Features.enabled?(:signups)
    end
  end
end
