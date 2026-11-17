# Reads the inventory settings registered in config/initializers/inventory.rb.
# A setting that doesn't parse falls back to its default rather than
# breaking every inventory page.
module Inventory
  module Config
    KINDS = %w[used moved counted received added removed].freeze
    DEFAULT_MEMBER_KINDS = %w[used moved counted].freeze
    UNIT_ACTIONS = %w[install take_off move check mark_for_repair repaired retire].freeze
    DEFAULT_MEMBER_UNIT_ACTIONS = %w[install take_off move check mark_for_repair].freeze
    REORDER_NOTICES = %w[off each daily weekly].freeze
    REORDER_NOTICE_CHOICES = [ [ "Off", "off" ], [ "An email each time", "each" ], [ "In the daily digest", "daily" ],
      [ "In the Weekly Infodump", "weekly" ] ].freeze
    DEFAULT_UNDO_MINUTES = 10

    module_function

    # Teams whose members (and the members of teams below) may use
    # inventory, or nil for everyone signed in.
    def user_teams
      names = Settings[:inventory_users].to_s.split(/[\n,]/).map(&:strip).compact_blank
      return nil if names.empty?

      Team.where(name: names).to_a
    end

    def managers
      Inventory::Reach.new(Settings[:inventory_managers].to_s.split("\n"))
    end

    def member_kinds
      list(Settings[:inventory_member_kinds], KINDS)
    end

    def member_unit_actions
      list(Settings[:inventory_member_unit_actions], UNIT_ACTIONS)
    end

    def used_needs_reason?
      ActiveModel::Type::Boolean.new.cast(Settings[:inventory_used_needs_reason]) || false
    end

    def undo_minutes
      minutes = Integer(Settings[:inventory_undo_minutes].to_s, exception: false)
      minutes.nil? || minutes.negative? ? DEFAULT_UNDO_MINUTES : minutes
    end

    # off, each, daily or weekly (in the Weekly Infodump, when summaries are on).
    def reorder_notice
      value = Settings[:inventory_reorder_notice].to_s.strip.downcase
      REORDER_NOTICES.include?(value) ? value : "daily"
    end

    # The default stock unit's name. Kept for features written against the
    # old inventory_default_unit setting; new code uses StockUnit.default_unit.
    def default_unit
      StockUnit.default_unit&.name || "each"
    end

    # The known names in a comma- or line-separated setting, in the
    # setting's order. Words with spaces ("take off") match their key.
    def list(value, known)
      value.to_s.split(/[\n,]/).map { |entry| entry.strip.downcase.tr(" ", "_") }.select { |entry| known.include?(entry) }.uniq
    end
  end
end
