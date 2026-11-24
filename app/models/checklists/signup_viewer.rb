module Checklists
  # Who is looking at sign-up rules, for Checklists::SignupRule: the viewer
  # of the sheet page or the roster (placing true on the roster's placing
  # pages), or whoever places or moves a sign-up
  # (Checklists::SignupPlacement). Unset elsewhere, where the rule gives its
  # real answer. sheet is true on the sheet page and when signing up from
  # it, whose reasons are for the people signing up rather than the sheet's
  # organizers. Reset
  # with every request.
  class SignupViewer < ActiveSupport::CurrentAttributes
    attribute :person, :placing, :sheet
  end
end
