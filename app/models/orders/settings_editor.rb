# Reads and writes the orders settings shown on Orders setup: who can ask,
# who sees every request, who approves (one step, plus an optional second one over an amount), who
# buys and how purchases are paid. It writes the same text and JSON the
# readers in Orders::Config parse, and leaves a setting's saved text as it
# is when the form says the same thing, so opening the page and saving
# changes nothing. #save checks what it's given and leaves the settings
# alone when anything is wrong.
#
# Where the settings pickers are available (Settings.input), the page draws
# teams and badge grants with them; otherwise with one-per-line text boxes.
module Orders
  class SettingsEditor
    FIRST_STEP_NAME = "Approval".freeze
    SECOND_STEP_NAME = "Large purchase".freeze

    # Stands in for a Settings::Setting so a picker can draw a value that
    # isn't a setting of its own, such as one step's approvers.
    Field = Struct.new(:setting_key, :name, :value, :default_value, keyword_init: true)

    FIELDS = {
      requesters: "Teams whose members (and members of the teams below) can ask. Leave empty for everyone signed in.",
      viewers: "Teams whose members (and members of the teams below) see every request, without approving or buying. Leave empty for nobody extra.",
      approvers: "Team managers can always approve. Also:",
      large_approvers: "Team managers can always approve. Also:",
      buyers: "Team managers can always buy. Also:"
    }.freeze

    TEAM_FIELDS = %i[requesters viewers].freeze

    attr_reader :large_amount, :paid_with, :errors

    def self.pickers?
      Settings.respond_to?(:input) && defined?(SettingInput::BadgeGrants).present?
    end

    # Whether the Orders menu has the Setup item. Menu items can only be
    # hidden from non-admins where NavItem takes a visible check; elsewhere
    # the Reports page links here instead.
    def self.in_menu?
      GatherPack::Feature::NavItem.members.include?(:visible)
    end

    def initialize
      @errors = []
      @steps = Orders::Config.approval_steps
      @texts = {
        requesters: Settings[:orders_requesters].to_s,
        viewers: Settings[:orders_viewers].to_s,
        approvers: @steps.first.approvers.join("\n"),
        large_approvers: @steps.second&.approvers.to_a.join("\n"),
        buyers: Settings[:orders_buyers].to_s
      }
      @saved_texts = @texts.dup
      @large_amount = @steps.second ? format("%g", @steps.second.minimum_cents / 100.0) : ""
      @paid_with = Orders::Config.paid_with.map { |choice| { "label" => choice.label, "reimburse" => choice.reimburse } }
      @saved_paid_with = @paid_with
    end

    # The saved steps, as Orders::Config reads them.
    attr_reader :steps

    # Whether the saved steps are ones this page can show: a first step for
    # every request and at most one more over an amount. Others are listed
    # read-only, and saving replaces them.
    def steps_fit?
      first, second, *rest = steps
      rest.empty? && first.minimum_cents.zero? && (second.nil? || second.minimum_cents.positive?)
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
      @large_amount = params[:large_amount].to_s.strip.delete_prefix("$").delete(",")
      @paid_with = rows(params[:paid_with]).filter_map { |row| paid_with_from(row) }
      self
    end

    def save
      validate
      return false if errors.any?

      write(:orders_requesters, text(:requesters)) unless same_lines?(text(:requesters), @saved_texts[:requesters])
      write(:orders_viewers, text(:viewers)) unless same_lines?(text(:viewers), @saved_texts[:viewers])
      write(:orders_buyers, text(:buyers)) unless same_lines?(text(:buyers), @saved_texts[:buyers])
      write(:orders_approval_steps, JSON.generate(new_steps)) unless same_steps?(new_steps)
      write(:orders_paid_with, JSON.generate(paid_with)) unless paid_with == @saved_paid_with
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

    def rows(value)
      (value.respond_to?(:values) ? value.values : Array(value)).map { |row| row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row.to_h }
    end

    def paid_with_from(row)
      label = row["label"].to_s.strip
      return nil if label.blank? || row["remove"] == "1"

      { "label" => label, "reimburse" => ActiveModel::Type::Boolean.new.cast(row["reimburse"]) || false }
    end

    def validate
      @errors = []
      errors << "Keep at least one way a purchase can be paid." if paid_with.empty?
      if large_amount.present? && !(number?(large_amount) && large_amount.to_d.positive?)
        errors << "The amount for a second approval must be a number of dollars above zero."
      end
      { requesters: "Who can ask", viewers: "Who sees every request" }.each do |name, label|
        new_lines(name).each do |team_name|
          errors << "#{label}: no team named \"#{team_name}\"." unless Team.exists?(name: team_name)
        end
      end
      validate_grants(:approvers, "Who approves")
      validate_grants(:large_approvers, "Over $#{large_amount}") if large_amount.present?
      validate_grants(:buyers, "Who buys")
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

    # The first step keeps its key and name, and so does an existing second
    # step: approvals are stored by key. A new second step gets a key that
    # no step has and no approval on record uses, so a removed step's
    # approvals never pass to it.
    def new_steps
      @new_steps ||= begin
        first = steps.first
        list = [ step_hash(first.key, first.name.presence || FIRST_STEP_NAME, 0, lines(text(:approvers))) ]
        if large_amount.present?
          second = steps.second
          list << step_hash(second&.key || free_key(list.first["key"]), second&.name.presence || SECOND_STEP_NAME,
            whole_or_decimal(large_amount.to_d), lines(text(:large_approvers)))
        end
        list
      end
    end

    def step_hash(key, name, minimum, approvers)
      { "key" => key, "name" => name, "minimum" => minimum, "approvers" => approvers }
    end

    def same_steps?(list)
      steps.map { |step| [ step.key, step.name, step.minimum_cents, step.approvers ] } ==
        list.map { |step| [ step["key"], step["name"], (step["minimum"].to_d * 100).round, step["approvers"] ] }
    end

    def free_key(first_key)
      taken = [ first_key ] | steps.map(&:key) | OrderApproval.distinct.pluck(:step_key) | OrderRequestEvent.where.not(step_key: nil).distinct.pluck(:step_key)
      base = SECOND_STEP_NAME.parameterize(separator: "_")
      key = base
      number = 1
      key = "#{base}_#{number += 1}" while taken.include?(key)
      key
    end

    def whole_or_decimal(amount)
      amount.frac.zero? ? amount.to_i : amount.to_f
    end

    def number?(text)
      text.to_s.strip.match?(/\A\d+(\.\d+)?\z/)
    end
  end
end
