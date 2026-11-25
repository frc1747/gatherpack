require "csv"

# The orders reports (spec §3.12). Each is a list of tables (title, headers
# and rows) so one page and one CSV writer serve them all. Rows hold Money,
# Date and plain values. Pass the viewer's person: they see only requests
# for teams they staff (every team for an admin).
module Orders
  class Reports
    Table = Struct.new(:title, :headers, :rows, keyword_init: true)
    Report = Struct.new(:key, :title, :description, :tables, keyword_init: true)

    KEYS = %w[open spending overdue non_preferred].freeze
    TITLES = {
      "open" => "Open requests",
      "spending" => "Spending",
      "overdue" => "Overdue items",
      "non_preferred" => "Non-preferred store spending"
    }.freeze
    DESCRIPTIONS = {
      "open" => "Requests that aren't finished, by status and how long since they were submitted",
      "spending" => "What's been bought, by store, team and month, with shipping and tax shown apart",
      "overdue" => "Items still waiting past the date they were needed by",
      "non_preferred" => "Money spent at stores that aren't preferred"
    }.freeze
    AGE_BANDS = [ [ "Up to 7 days", 0..7 ], [ "8 to 14 days", 8..14 ], [ "15 to 30 days", 15..30 ], [ "Over 30 days", 31..Float::INFINITY ] ].freeze
    WAITING_LINES = %w[approved ordered backordered partly_received problem needs_reapproval].freeze
    # One bought line with its share of its order's shipping and tax.
    Spent = Struct.new(:line, :purchase, :team, :vendor_name, :month, :goods_cents, :shipping_cents, :tax_cents, keyword_init: true) do
      def total_cents = goods_cents + shipping_cents + tax_cents
    end

    def initialize(person, today: Date.current)
      @person = person
      @today = today
    end

    def self.find(key)
      KEYS.include?(key.to_s) ? key.to_s : nil
    end

    # One CSV for a report: each table under its title.
    def self.to_csv(report)
      CSV.generate do |csv|
        csv << [ report.title ]
        report.tables.each do |table|
          csv << []
          csv << [ table.title ]
          csv << table.headers
          table.rows.each { |row| csv << row.map { |value| csv_value(value) } }
        end
      end
    end

    # Text that a spreadsheet would run as a formula gets a leading quote.
    def self.csv_value(value)
      case value
      when Money then format("%.2f", value.to_d)
      when Date then value.iso8601
      when String then value.match?(/\A[=+\-@\t\r]/) ? "'#{value}" : value
      else value
      end
    end

    def report(key)
      key = self.class.find(key) or raise ActiveRecord::RecordNotFound
      Report.new(key: key, title: TITLES[key], description: DESCRIPTIONS[key], tables: send("#{key}_tables"))
    end

    # The team ids shown, or nil for all.
    def team_ids
      return @team_ids if defined?(@team_ids)

      access = Orders::Access.for(@person)
      @team_ids = access.admin? ? nil : (access.managed_team_ids | access.any_approver_team_ids | access.buyer_team_ids | access.funding_manager_team_ids).to_a
    end

    private

    def requests
      scope = OrderRequest.all
      team_ids ? scope.where(team_id: team_ids) : scope
    end

    def open_tables
      list = requests.open.includes(:team, :requested_by, :order_lines).to_a
      by_status = OrderRequest::ACTIVE_STATUSES.excluding("draft").filter_map do |status|
        group = list.select { |request| request.status == status }
        next if group.empty?

        [ OrdersHelper::REQUEST_STATUS_WORDS[status], group.size, *AGE_BANDS.map { |_, days| group.count { |request| days.cover?(age_days(request)) } }, Money.new(group.sum(&:total_cents)) ]
      end
      [
        Table.new(title: "By status and age", headers: [ "Status", "Requests", *AGE_BANDS.map(&:first), "Total" ], rows: by_status),
        Table.new(title: "Oldest first", headers: [ "Request", "Team", "Requested by", "Status", "Days open", "Needed by", "Total" ],
          rows: list.sort_by { |request| -age_days(request) }.map do |request|
            [ request.display_title, request.team.name, request.requested_by.display_name, OrdersHelper::REQUEST_STATUS_WORDS[request.status],
              age_days(request), request.needed_by, Money.new(request.total_cents) ]
          end)
      ]
    end

    def age_days(request)
      (@today - (request.submitted_at || request.created_at).to_date).to_i
    end

    def spending_tables
      [
        spending_table("By store", "Store") { |spent| spent.vendor_name },
        spending_table("By team", "Team") { |spent| spent.team.name },
        spending_table("By month", "Month", chronological: true) { |spent| spent.month }
      ]
    end

    def spending_table(title, heading, chronological: false, &key)
      groups = spent_lines.group_by(&key)
      groups = chronological ? groups.sort_by(&:first) : groups.sort_by { |name, spent| [ -spent.sum(&:total_cents), name.to_s ] }
      rows = groups.map { |name, spent| [ name.is_a?(Date) ? name.strftime("%B %Y") : name, *money_columns(spent) ] }
      rows << [ "All", *money_columns(spent_lines) ] if rows.size > 1
      Table.new(title: title, headers: [ heading, "Items", "Goods", "Shipping", "Tax", "Total" ], rows: rows)
    end

    def money_columns(spent)
      [ spent.size, *%i[goods_cents shipping_cents tax_cents total_cents].map { |field| Money.new(spent.sum(&field)) } ]
    end

    # Every bought line, with shipping and tax shared out as on the order.
    def spent_lines
      @spent_lines ||= begin
        lines = OrderLine.where.not(purchase_id: nil).joins(:order_request).merge(requests).includes(:vendor, :order_request, purchase: [ :vendor, :order_lines ]).to_a
        lines.filter_map do |line|
          purchase = line.purchase
          share = purchase.extras_shares.fetch(line.id, 0)
          extras = purchase.extras_cents
          shipping = extras.zero? ? 0 : (share * purchase.shipping_cents.to_i / extras.to_f).round
          Spent.new(line: line, purchase: purchase, team: line.order_request.team, vendor_name: purchase.vendor_name || "Unknown",
            month: (purchase.ordered_on || purchase.created_at.to_date).beginning_of_month,
            goods_cents: line.cost_cents, shipping_cents: shipping, tax_cents: share - shipping)
        end
      end
    end

    def overdue_tables
      lines = OrderLine.where(status: WAITING_LINES).joins(:order_request).merge(requests)
        .where(order_requests: { status: %w[approved ordering] }).where("order_requests.needed_by < ?", @today)
        .includes(:vendor, :purchase, order_request: %i[team requested_by]).to_a
        .sort_by { |line| line.order_request.needed_by }
      [ Table.new(title: "Past their needed-by date", headers: [ "Item", "Request", "Team", "Needed by", "Days late", "Status", "Store", "Expected" ],
        rows: lines.map do |line|
          request = line.order_request
          [ line.display_name, request.display_title, request.team.name, request.needed_by, (@today - request.needed_by).to_i,
            OrdersHelper::LINE_STATUS_WORDS[line.status], line.vendor_name, line.expected_on || line.purchase&.expected_on ]
        end) ]
    end

    def non_preferred_tables
      spent = spent_lines.reject { |row| row.purchase.vendor&.preferred? }
      by_store = spent.group_by(&:vendor_name).sort_by { |name, rows| [ -rows.sum(&:total_cents), name ] }
        .map { |name, rows| [ name, *money_columns(rows) ] }
      [
        Table.new(title: "By store", headers: [ "Store", "Items", "Goods", "Shipping", "Tax", "Total" ], rows: by_store),
        Table.new(title: "Items", headers: [ "Bought on", "Item", "Store", "Request", "Team", "Total" ],
          rows: spent.sort_by { |row| row.purchase.ordered_on || row.month }.map do |row|
            [ row.purchase.ordered_on, row.line.display_name, row.vendor_name, row.line.order_request.display_title, row.team.name, Money.new(row.total_cents) ]
          end)
      ]
    end
  end
end
