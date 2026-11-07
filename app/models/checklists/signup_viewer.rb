module Checklists
  # Who is looking at sign-up rules other than through the sheet's own
  # sign-up gate, for Checklists::SignupRule: the organizer on the roster
  # pages (placing true while they place or move someone), or the person
  # placing a sign-up (Checklists::SignupPlacement). Unset elsewhere, where
  # the rule gives its real answer. Reset with every request.
  class SignupViewer < ActiveSupport::CurrentAttributes
    attribute :person, :placing
  end
end
