# Connects Checklists to Sign-up Sheets (checklists spec §10.3): a position
# rule kind "checklist" (only people who finish it take the place), and a
# panel on the sheet page saying what's left and how to fix it. Organizers
# see a rule's answer for someone on the roster only when they may see that
# person's result (Checklists::SignupRule). A checklist
# a rule needs counts as in use: it can't be deleted, and housekeeping
# doesn't archive it while a sheet needs it (feature/checklists has no
# "in use" registry, so this hooks Housekeeping.archive_due?). The rule and
# panel stay quiet while Checklists are off; a checklist rule then fails with its
# reason rather than letting everyone through.
Rails.application.config.to_prepare do
  next unless defined?(Checklists) && Checklists.respond_to?(:register_item_kind) && defined?(Signups)

  SignupPositionRule.prepend(Checklists::SignupRule)
  SignupPositionRulesController.prepend(Checklists::SignupPositionRules)
  Signup.prepend(Checklists::SignupPlacement)
  # The roster shows rules' answers to organizers, as each may see them.
  SignupSheetsController.before_action(only: :roster) { Checklists::SignupViewer.person = current_user&.person }
  RosterSignupsController.before_action do
    Checklists::SignupViewer.person = current_user&.person
    Checklists::SignupViewer.placing = true
  end
  Checklist.prepend(Checklists::UsedBySignupRules)
  Checklists::Housekeeping.singleton_class.prepend(Checklists::SignupRuleHousekeeping)
  Signups.extensions.register_sheet_panel(:checklists, partial: "signup_checklists/sheet_panel")
end
