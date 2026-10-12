module Commitments
  # Who is looking at the sign up dialog, for SignupHint: the hint slot
  # (Signups.extensions) passes only the sheet and the candidate, and a
  # person's progress isn't for everyone. Set for each sign-ups request by
  # config/initializers/signup_credit.rb.
  class SignupViewer < ActiveSupport::CurrentAttributes
    attribute :person
  end
end
