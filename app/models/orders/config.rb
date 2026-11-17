# Reads the orders settings registered in config/initializers/orders.rb,
# and the approval steps (ApprovalStep rows). A setting that doesn't parse
# falls back to its default rather than breaking every orders page.
module Orders
  module Config
    Tolerance = Struct.new(:percent, :amount_cents, keyword_init: true) do
      # The most a total may rise over approved_cents without approving again.
      def allowance_cents(approved_cents)
        [ (approved_cents.to_i * percent / 100.0).round, amount_cents ].max
      end
    end

    DEFAULT_TOLERANCE = "10%, 25"

    module_function

    # The active approval steps (ApprovalStep rows) in order, with their
    # approvers loaded. With none active, ApprovalStep.fallback: admins and
    # team managers approve every request.
    def approval_steps
      steps = ApprovalStep.active.ordered.includes(approvers: %i[badge team]).to_a
      steps.presence || [ ApprovalStep.fallback ]
    end

    # The step with this key, retired or not, so old approvals still find
    # their step's current name.
    def step(key)
      ApprovalStep.find_by(key: key.to_s) || (ApprovalStep.fallback if key.to_s == ApprovalStep.fallback.key)
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
  end
end
