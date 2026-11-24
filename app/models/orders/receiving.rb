# The items a person can receive (spec §3.6, §3.12), grouped by the purchase
# they're on. With mine: true it holds only items on their own and followed
# requests, the same ones Orders::WaitingOn counts as "to receive", so the
# Home row and the list it opens agree.
#
#   receiving = Orders::Receiving.new(user, scope, mine: true)
#   receiving.groups   # [Group(purchase:, lines:)], soonest expected first
#   receiving.count
module Orders
  class Receiving
    Group = Struct.new(:purchase, :lines, keyword_init: true) do
      def expected_on
        lines.filter_map { |line| line.expected_on || purchase&.expected_on }.min
      end
    end

    FINISHED = %w[draft closed declined cancelled].freeze

    # scope is the requests the person may see (policy_scope(OrderRequest)).
    def initialize(user, scope, mine: false)
      @user = user
      @person = user.person
      @scope = scope
      @mine = mine
    end

    def groups
      @groups ||= lines.group_by(&:purchase).map { |purchase, items| Group.new(purchase: purchase, lines: items) }
        .sort_by { |group| [ group.expected_on ? 0 : 1, group.expected_on || Date.new(0), group.purchase&.created_at.to_f ] }
    end

    def lines
      @lines ||= requests.flat_map { |order_request| order_request.order_lines.select(&:open_to_receive?) }
    end

    def count
      lines.size
    end

    def requests
      @requests ||= begin
        candidates = @scope.where.not(status: FINISHED)
          .includes(:team, :order_request_watchers, order_lines: [ { purchase: :vendor }, :vendor, :order_deliveries ]).to_a
        candidates = candidates.select { |order_request| own_or_followed?(order_request) } if @mine
        candidates.select { |order_request| OrderRequestPolicy.new(@user, order_request).receive? }
      end
    end

    private

    def own_or_followed?(order_request)
      order_request.requested_by_id == @person.id || order_request.watched_by?(@person)
    end
  end
end
