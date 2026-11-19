module Signups
  # Announces signup_sheet_changed.gatherpack when a sheet's positions,
  # slots or events change (spec §3.9). The including model says which sheet
  # through #changed_signup_sheet_id.
  module SheetChanges
    extend ActiveSupport::Concern

    included do
      after_create_commit -> { Signups.sheet_changed(changed_signup_sheet_id, self, :created) }
      after_update_commit -> { Signups.sheet_changed(changed_signup_sheet_id, self, :updated) }
      after_destroy_commit -> { Signups.sheet_changed(changed_signup_sheet_id, self, :destroyed) }
    end
  end
end
