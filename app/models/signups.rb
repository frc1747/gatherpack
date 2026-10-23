# The seams the sign-up layer offers other features (spec §3.9), so they can
# add to sign-up pages without editing sign-up views. Register from a
# config.to_prepare block, as features do with GatherPack::Features, so the
# registrations come back after a development reload:
#
#   Rails.application.config.to_prepare do
#     # Rendered under My sign-ups on the sheet page, with the locals
#     # signup_sheet: and viewer:. The partial may render nothing.
#     Signups.extensions.register_sheet_panel(:my_feature, partial: "my_feature/sheet_panel")
#
#     # Short text next to each on-behalf-of choice in the sign up dialog,
#     # or nil for none.
#     Signups.extensions.register_on_behalf_of_hint(:my_feature, ->(sheet, person) { "2 to go" })
#   end
#
# Registering the same key again replaces the earlier entry.
module Signups
  class Extensions
    SheetPanel = Struct.new(:key, :partial, keyword_init: true)
    OnBehalfOfHint = Struct.new(:key, :hint, keyword_init: true)

    def initialize
      reset!
    end

    def register_sheet_panel(key, partial:)
      @sheet_panels[key.to_sym] = SheetPanel.new(key: key.to_sym, partial: partial)
    end

    def register_on_behalf_of_hint(key, hint)
      @on_behalf_of_hints[key.to_sym] = OnBehalfOfHint.new(key: key.to_sym, hint: hint)
    end

    def sheet_panels
      @sheet_panels.values
    end

    def on_behalf_of_hints
      @on_behalf_of_hints.values
    end

    # The hints for this person, joined, or nil when there are none.
    def on_behalf_of_hint(sheet, person)
      on_behalf_of_hints.filter_map { |entry| entry.hint.call(sheet, person).presence }.join("; ").presence
    end

    def reset!
      @sheet_panels = {}
      @on_behalf_of_hints = {}
    end
  end

  def self.extensions
    @extensions ||= Extensions.new
  end

  # Notifications other features recompute from:
  #
  #   signup_changed.gatherpack        signup:, change: (:created, :status,
  #                                    :moved, :cancelled or :changed)
  #   signup_sheet_changed.gatherpack  signup_sheet_id:, record:, change:
  #                                    (a position, slot, sheet event or event
  #                                    was :created, :updated or :destroyed, or
  #                                    an event's :event_time changed)
  def self.signup_changed(signup, change)
    ActiveSupport::Notifications.instrument("signup_changed.gatherpack", signup: signup, change: change)
  end

  def self.sheet_changed(signup_sheet_id, record, change)
    return if signup_sheet_id.nil?

    ActiveSupport::Notifications.instrument("signup_sheet_changed.gatherpack", signup_sheet_id: signup_sheet_id, record: record, change: change)
  end
end
