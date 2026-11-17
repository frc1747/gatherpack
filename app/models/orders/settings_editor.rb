# Reads and writes the orders settings shown on Orders setup: who can ask,
# who sees every request, who buys, who manages funding sources, and the
# plain yes/no and number settings in SECTIONS. Approval steps, payment
# methods and delivery problems are managed lists with screens of their own,
# which the page links to. Every setting in the "Orders"
# group is on the page: one that isn't in the list above or in SECTIONS is
# drawn under "More settings", so a new orders setting can't be left off.
# It writes the same text the readers in Orders::Config parse, and
# leaves a setting's saved text as it is when the form says the same thing,
# so opening the page and saving changes nothing. #save checks what it's
# given and leaves the settings alone when anything is wrong.
#
# Where the settings pickers are available (Settings.input), the page draws
# teams and badge grants with them; otherwise with one-per-line text boxes.
module Orders
  class SettingsEditor
    # Stands in for a Settings::Setting so a picker can draw a value that
    # isn't a setting of its own, such as the buyers.
    Field = Struct.new(:setting_key, :name, :value, :default_value, keyword_init: true)

    FIELDS = {
      requesters: "Teams whose members (and members of the teams below) can ask. Leave empty for everyone signed in.",
      viewers: "Teams whose members (and members of the teams below) see every request, without approving or buying. Leave empty for nobody extra.",
      buyers: "Team managers can always buy. Also:",
      funding_managers: "Team managers can always manage funding sources. Also:"
    }.freeze

    # What the blank team choice of a badge grant means for orders.
    BLANK_TEAM_LABEL = "Up to: every team".freeze

    # The orders settings with a box of their own (not a badge grant or team
    # list, which have fields above), in the order the page draws them.
    SECTIONS = [
      [ "Seeing requests", %i[orders_team_can_see] ],
      [ "Buying", %i[orders_price_tolerance orders_require_other_vendor_reason] ],
      [ "Funding", %i[orders_require_funding_source orders_requesters_pick_funding] ],
      [ "Closing", %i[orders_close_after_days] ]
    ].freeze

    # Settings drawn by a partial of their own, with locals setting, value
    # and prefix (the names of the fields it posts).
    PARTIALS = { orders_price_tolerance: "orders/settings/price_tolerance" }.freeze

    # Orders settings the page draws with the fields above.
    FIELD_SETTINGS = %i[orders_requesters orders_viewers orders_buyers orders_funding_managers].freeze

    TEAM_FIELDS = %i[requesters viewers].freeze

    attr_reader :errors, :values

    # The settings in the "Orders" group that SECTIONS lists, grouped, then
    # any others as "More settings".
    def self.sections
      listed = SECTIONS.flat_map(&:last) + FIELD_SETTINGS
      extra = Settings.settings("Orders").map(&:setting_key) - listed
      list = SECTIONS.map { |heading, keys| [ heading, keys.filter_map { |key| Settings.get(key) } ] }
      list << [ "More settings", extra.filter_map { |key| Settings.get(key) } ] if extra.any?
      list.reject { |_, settings| settings.empty? }
    end

    def self.section_keys
      sections.flat_map { |_, settings| settings.map(&:setting_key) }
    end

    def self.pickers?
      Settings.respond_to?(:input) && defined?(SettingInput::BadgeGrants).present?
    end

    # Whether menu items take a visible check, so the orders items most
    # members can't use (To approve, To buy, Reports) can be hidden.
    def self.in_menu?
      GatherPack::Feature::NavItem.members.include?(:visible)
    end

    def initialize
      @errors = []
      @texts = {
        requesters: Settings[:orders_requesters].to_s,
        viewers: Settings[:orders_viewers].to_s,
        buyers: Settings[:orders_buyers].to_s,
        funding_managers: Settings[:orders_funding_managers].to_s
      }
      @saved_texts = @texts.dup
      @values = self.class.section_keys.index_with { |key| saved_value(key) }
    end

    def text(name)
      @texts.fetch(name)
    end

    # The picker for one of FIELDS, drawn from the text the form holds.
    def picker(name)
      field = Field.new(setting_key: name.to_s, name: FIELDS.fetch(name), value: text(name), default_value: "")
      TEAM_FIELDS.include?(name) ? SettingInput::Teams.new(field) : SettingInput::BadgeGrants.new(field, badges: -> { Badge.added_by_admin })
    end

    def assign(params)
      posted = params[:settings] || {}
      FIELDS.each_key do |name|
        @texts[name] = text_from(name, posted[name]) if posted.key?(name)
      end
      posted_values = params[:values].respond_to?(:to_unsafe_h) ? params[:values].to_unsafe_h : params[:values].to_h
      @values = values.to_h { |key, value| [ key, value_from(key, posted_values.fetch(key.to_s, value), value) ] }
      self
    end

    def save
      validate
      return false if errors.any?

      write(:orders_requesters, text(:requesters)) unless same_lines?(text(:requesters), @saved_texts[:requesters])
      write(:orders_viewers, text(:viewers)) unless same_lines?(text(:viewers), @saved_texts[:viewers])
      write(:orders_buyers, text(:buyers)) unless same_lines?(text(:buyers), @saved_texts[:buyers])
      write(:orders_funding_managers, text(:funding_managers)) unless same_lines?(text(:funding_managers), @saved_texts[:funding_managers])
      values.each { |key, value| write(key, value) unless value == saved_value(key) }
      true
    end

    private

    def write(key, value)
      Settings[key] = value
    end

    # A picker turns what it posts into the setting's text (and keeps the
    # saved text when nothing changed); a text box posts the text itself.
    def text_from(name, posted)
      self.class.pickers? ? picker(name).text_from(posted, @saved_texts[name]) : posted.to_s
    end

    def validate
      @errors = []
      { requesters: "Who can ask", viewers: "Who sees every request" }.each do |name, label|
        new_lines(name).each do |team_name|
          errors << "#{label}: no team named \"#{team_name}\"." unless Team.exists?(name: team_name)
        end
      end
      validate_grants(:buyers, "Who buys")
      validate_grants(:funding_managers, "Who manages funding sources")
      values.each { |key, value| validate_value(Settings.get(key), value) }
      errors << "#{Settings.get(:orders_price_tolerance).name}: use numbers for the percentage and the amount." if @tolerance_invalid
    end

    # What the form posted for a setting, as text. A setting drawn by a
    # partial of its own posts fields, which turn into its text.
    def value_from(key, posted, current)
      if key == :orders_price_tolerance && (posted.respond_to?(:to_unsafe_h) || posted.is_a?(Hash))
        @tolerance_invalid = !Orders::PriceToleranceField.valid?(posted)
        Orders::PriceToleranceField.text_from(posted, current)
      else
        posted.to_s.strip
      end
    end

    # A saved value as the page holds it: yes/no settings as "true"/"false".
    def saved_value(key)
      setting = Settings.get(key)
      setting.setting_type == :boolean ? setting.value.to_s : setting.value.to_s.strip
    end

    def validate_value(setting, value)
      case setting.setting_type
      when :boolean
        errors << "#{setting.name}: choose yes or no." unless %w[true false].include?(value)
      when :integer
        errors << "#{setting.name}: must be a whole number, zero or more." unless value.match?(/\A\d+\z/)
      end
    end

    # Only lines that weren't saved before are checked, so a saved line whose
    # badge or team has since gone doesn't block saving the rest.
    def validate_grants(name, label)
      new_lines(name).each do |line|
        badge_name, team_name = line.split(">", 2).map(&:strip)
        errors << "#{label}: no badge given in \"#{line}\"." if badge_name.blank?
        errors << "#{label}: no badge named \"#{badge_name}\" that admins assign." if badge_name.present? && !Badge.added_by_admin.exists?([ "LOWER(name) = ?", badge_name.downcase ])
        errors << "#{label}: no team named \"#{team_name}\"." if team_name.present? && !Team.exists?(name: team_name)
      end
    end

    def new_lines(name)
      lines(text(name)) - lines(@saved_texts[name])
    end

    def lines(text)
      text.to_s.lines.map(&:strip).compact_blank
    end

    def same_lines?(text, saved)
      lines(text) == lines(saved)
    end
  end
end
