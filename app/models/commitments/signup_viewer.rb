module Commitments
  # Who is looking at the sign up dialog, and for which slot, for
  # SignupHint: the hint slot (Signups.extensions) passes only the sheet and
  # the candidate, a person's progress isn't for everyone, and only some
  # commitments credit a sign-up to a given slot. Set for each sign-ups
  # request by config/initializers/signup_credit.rb.
  class SignupViewer < ActiveSupport::CurrentAttributes
    attribute :person, :slot
  end
end
