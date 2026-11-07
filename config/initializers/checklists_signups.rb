# Connects Checklists to Sign-up Sheets (checklists spec §10.3): a position
# rule kind "checklist" (only people who finish it take the place), and a
# panel on the sheet page saying what's left and how to fix it. Both stay
# quiet while Checklists are off; a checklist rule then fails with its
# reason rather than letting everyone through.
Rails.application.config.to_prepare do
  next unless defined?(Checklists) && Checklists.respond_to?(:register_item_kind) && defined?(Signups)

  SignupPositionRule.prepend(Checklists::SignupRule)
  SignupPositionRulesController.prepend(Checklists::SignupPositionRules)
  Checklist.include(Checklists::UsedBySignupRules)
  Signups.extensions.register_sheet_panel(:checklists, partial: "signup_checklists/sheet_panel")
end
