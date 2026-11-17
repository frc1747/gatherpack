# Reads the orders settings registered in config/initializers/orders.rb.
# A setting that doesn't parse falls back to its default rather than
# breaking every orders page.
module Orders
  module Config
    Step = Struct.new(:key, :name, :minimum_cents, :approvers, keyword_init: true) do
      # The Orders::Reach for this step's approver grants.
      def reach
        @reach ||= Orders::Reach.new(approvers)
      end
    end

    PaidWith = Struct.new(:label, :reimburse, keyword_init: true)
    Tolerance = Struct.new(:percent, :amount_cents, keyword_init: true) do
      # The most a total may rise over approved_cents without approving again.
      def allowance_cents(approved_cents)
        [ (approved_cents.to_i * percent / 100.0).round, amount_cents ].max
      end
    end

    DEFAULT_STEPS = [ { "key" => "approval", "name" => "Approval", "minimum" => 0, "approvers" => [] } ].freeze
    DEFAULT_PAID_WITH = [
      { "label" => "Team card", "reimburse" => false },
      { "label" => "Personal card — reimburse", "reimburse" => true }
    ].freeze
    DEFAULT_TOLERANCE = "10%, 25"

    module_function

    # The approval steps in order. Each is a JSON object with a stable key,
    # a name, a minimum request total in currency units (0 means always) and
    # its approver grants, as "Badge name > Team name" strings (Orders::Reach).
    def approval_steps
      parsed = parse_json(Settings[:orders_approval_steps], DEFAULT_STEPS)
      steps = Array(parsed).filter_map do |entry|
        next unless entry.is_a?(Hash) && entry["key"].present?

        Step.new(key: entry["key"].to_s, name: entry["name"].presence || entry["key"].to_s.humanize,
          minimum_cents: (entry["minimum"].to_d * 100).round, approvers: Array(entry["approvers"]).map(&:to_s))
      end
      steps.presence || approval_steps_from(DEFAULT_STEPS)
    end

    def approval_steps_from(list)
      list.map do |entry|
        Step.new(key: entry["key"], name: entry["name"], minimum_cents: (entry["minimum"].to_d * 100).round, approvers: entry["approvers"])
      end
    end

    def step(key)
      approval_steps.find { |step| step.key == key.to_s }
    end

    def paid_with
      parsed = parse_json(Settings[:orders_paid_with], DEFAULT_PAID_WITH)
      choices = Array(parsed).filter_map do |entry|
        next unless entry.is_a?(Hash) && entry["label"].present?

        PaidWith.new(label: entry["label"].to_s, reimburse: ActiveModel::Type::Boolean.new.cast(entry["reimburse"]) || false)
      end
      choices.presence || DEFAULT_PAID_WITH.map { |entry| PaidWith.new(label: entry["label"], reimburse: entry["reimburse"]) }
    end

    # "10%, 25": a percentage and an amount; the larger applies. Either may
    # be left out.
    def price_tolerance
      text = Settings[:orders_price_tolerance].presence || DEFAULT_TOLERANCE
      percent = 0
      amount_cents = 0
      text.to_s.split(/[,;]/).map(&:strip).each do |part|
        number = part[/\d+(\.\d+)?/]
        next unless number

        if part.include?("%")
          percent = number.to_d
        else
          amount_cents = (number.to_d * 100).round
        end
      end
      Tolerance.new(percent: percent, amount_cents: amount_cents)
    end

    def buyers
      Orders::Reach.new(grant_lines(Settings[:orders_buyers]))
    end

    def funding_managers
      Orders::Reach.new(grant_lines(Settings[:orders_funding_managers]))
    end

    # The teams named in orders_requesters, or nil when it's blank
    # (everyone signed in may ask).
    def requester_teams
      names = grant_lines(Settings[:orders_requesters])
      return nil if names.empty?

      Team.where(name: names).to_a
    end

    # The teams named in orders_viewers: their members (and members of the
    # teams below) see every request that isn't a draft. Empty when blank.
    def viewer_teams
      names = grant_lines(Settings[:orders_viewers])
      names.empty? ? [] : Team.where(name: names).to_a
    end

    def team_can_see?
      Settings[:orders_team_can_see] != false
    end

    def require_other_vendor_reason?
      Settings[:orders_require_other_vendor_reason] == true
    end

    def require_funding_source?
      Settings[:orders_require_funding_source] == true
    end

    def requesters_pick_funding?
      Settings[:orders_requesters_pick_funding] == true
    end

    def close_after_days
      Settings[:orders_close_after_days].to_i.then { |days| days.positive? ? days : 14 }
    end

    def grant_lines(text)
      text.to_s.lines.map(&:strip).compact_blank
    end

    def parse_json(text, default)
      return default if text.blank?

      JSON.parse(text)
    rescue JSON::ParserError
      default
    end
  end
end
