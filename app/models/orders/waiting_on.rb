# Who is waiting on what (spec §3.15), for one person. The To approve and
# To buy pages, the My Orders card and the Home connector all read it, so
# they can't disagree.
#
#   waiting = Orders::WaitingOn.for(person)   # memoized for the web request
#   waiting.todos            # Row structs, by needed_by (none last)
#   waiting.todo_count
#   waiting.to_approve       # requests the person can decide now
#   waiting.to_reapprove     # requests with items needing re-approval
#   waiting.needing_changes  # the person's requests sent back to them
#   waiting.problems         # requests with a problem on a line they bought
#   waiting.lines_to_buy     # count of approved items within buyer reach
#   waiting.buy_lines        # those items, as a relation (the To buy page)
#   waiting.lines_to_receive # count on their own and followed requests
#   waiting.active_requests  # their own and followed requests still active
#
# It loads the candidate requests once, with their lines and approvals, and
# works out each one's current step in memory, so the number of queries
# doesn't grow with the number of requests.
module Orders
  class WaitingOn
    Row = Struct.new(:kind, :order_request, :count, :needed_by, :comment, keyword_init: true)

    attr_reader :person

    def self.for(person)
      return new(person) if person.nil?

      Orders::Current.waiting_on[person.id] ||= new(person)
    end

    def initialize(person)
      @person = person
      @access = Orders::Access.for(person)
    end

    def to_approve
      @to_approve ||= candidates.select { |order_request| order_request.submitted? && order_request.can_decide?(person, steps) }
        .sort_by { |order_request| by_need(order_request) }
    end

    def to_reapprove
      @to_reapprove ||= candidates.select do |order_request|
        order_request.needs_reapproval? && order_request.can_decide?(person, steps)
      end.sort_by { |order_request| by_need(order_request) }
    end

    def needing_changes
      @needing_changes ||= candidates.select { |order_request| order_request.changes_requested? && order_request.requested_by_id == person&.id }
    end

    def problems
      @problems ||= candidates.select do |order_request|
        order_request.order_lines.any? { |line| line.problem? && line.purchase&.buyer_id == person&.id }
      end
    end

    # Approved items not yet bought, on requests within the person's buyer
    # reach, as one count and the earliest needed_by.
    def lines_to_buy
      buy_queue[0]
    end

    def earliest_to_buy
      buy_queue[1]
    end

    # The approved, unbought items within the person's buyer reach.
    def buy_lines
      return OrderLine.none if person.nil? || !access.buyer?

      lines = OrderLine.joins(:order_request).where(status: :approved, purchase_id: nil)
        .where(order_requests: { status: %w[approved ordering received] })
      access.admin? ? lines : lines.where(order_requests: { team_id: access.buyer_team_ids.to_a })
    end

    # Items on a purchase, still to receive, on the person's own and
    # followed requests.
    def lines_to_receive
      @lines_to_receive ||= mine.sum { |order_request| order_request.order_lines.count(&:open_to_receive?) }
    end

    # Their own and followed requests that are active (drafts only their
    # own), most recently changed first.
    def active_requests
      @active_requests ||= mine.select { |order_request| order_request.status.in?(OrderRequest::ACTIVE_STATUSES) }
        .reject { |order_request| order_request.draft? && order_request.requested_by_id != person.id }
        .sort_by { |order_request| -order_request.updated_at.to_f }
    end

    def todos
      @todos ||= begin
        rows = to_approve.map { |order_request| row(:approve, order_request) }
        rows += to_reapprove.map { |order_request| row(:reapprove, order_request) }
        rows += needing_changes.map do |order_request|
          comment = order_request.active_approvals.select(&:changes_requested?).last&.comment
          row(:update, order_request, comment: comment)
        end
        rows << Row.new(kind: :buy, count: lines_to_buy, needed_by: earliest_to_buy) if lines_to_buy.positive?
        rows += problems.map { |order_request| row(:resolve, order_request) }
        if lines_to_receive.positive?
          rows << Row.new(kind: :receive, count: lines_to_receive, needed_by: mine.select { |r| r.order_lines.any?(&:open_to_receive?) }.filter_map(&:needed_by).min)
        end
        rows.sort_by { |todo| [ todo.needed_by ? 0 : 1, todo.needed_by || Date.new(0) ] }
      end
    end

    def todo_count
      todos.size
    end

    def any?
      todos.any? || active_requests.any?
    end

    private

    attr_reader :access

    def steps
      @steps ||= access.steps
    end

    def row(kind, order_request, comment: nil)
      Row.new(kind: kind, order_request: order_request, needed_by: order_request.needed_by, comment: comment)
    end

    def by_need(order_request)
      [ order_request.needed_by ? 0 : 1, order_request.needed_by || Date.new(0), order_request.submitted_at || order_request.created_at ]
    end

    # Every request any of the rows could come from, loaded once: their own
    # and followed requests, requests within approver reach that wait on a
    # decision, and requests with a problem on a line they bought.
    def candidates
      @candidates ||= begin
        return [] if person.nil?

        scope = OrderRequest.where(requested_by_id: person.id)
          .or(OrderRequest.where(id: OrderRequestWatcher.where(person_id: person.id).select(:order_request_id)))
          .or(OrderRequest.where(id: OrderLine.where(status: :problem, purchase_id: Purchase.where(buyer_id: person.id).select(:id)).select(:order_request_id)))
        if access.approver?
          waiting = OrderRequest.where(status: :submitted)
            .or(OrderRequest.where(status: %i[approved ordering], id: OrderLine.where(status: :needs_reapproval).select(:order_request_id)))
          waiting = waiting.where(team_id: access.any_approver_team_ids.to_a) unless access.admin?
          scope = scope.or(OrderRequest.where(id: waiting.select(:id)))
        end
        scope.where.not(status: %i[closed declined cancelled])
          .includes(:team, :order_request_watchers, :order_approvals, order_lines: :purchase).to_a
      end
    end

    def mine
      @mine ||= candidates.select { |order_request| order_request.requested_by_id == person&.id || order_request.watched_by?(person) }
    end

    def buy_queue
      @buy_queue ||= begin
        if person.nil? || !access.buyer?
          [ 0, nil ]
        else
          count, earliest = buy_lines.pick(Arel.sql("COUNT(*)"), Arel.sql("MIN(order_requests.needed_by)"))
          [ count.to_i, earliest ]
        end
      end
    end
  end
end
