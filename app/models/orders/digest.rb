# One person's Orders section of a summary (spec §3.11): the requests
# waiting for their approval, what's ready for them to buy, and what
# happened to the requests they made or follow since the last one. Built for
# the daily email and the Weekly Infodump (GatherPack::Digests) and for
# Orders' own daily email when Summaries is off.
#
#   digest = Orders::Digest.new(person, since: 1.day.ago)
#   digest.empty?
#   digest.body      # HTML, everything people typed escaped
module Orders
  class Digest
    include ERB::Util

    # Timeline entries that tell a requester something, and how a line in
    # "Your requests" names them.
    STATES = {
      "approved" => "approved",
      "changes_requested" => "changes requested",
      "declined" => "declined",
      "purchased" => "ordered",
      "backordered" => "delayed",
      "received" => "everything has arrived"
    }.freeze

    attr_reader :person, :since

    # The section for GatherPack::Digests, or nil when there's nothing for
    # the person.
    def self.section(person, since:)
      return unless Orders.enabled?

      digest = new(person, since: since)
      return if digest.empty?

      GatherPack::Digests::Section.new(heading: "Orders", body: digest.body,
        link: Rails.application.routes.url_helpers.orders_requests_url, link_label: "Open Orders")
    end

    def initialize(person, since:)
      @person = person
      @since = since
    end

    def empty?
      to_approve.empty? && to_buy.empty? && changes.empty?
    end

    # Submitted requests on a step the person approves, oldest first.
    def to_approve
      @to_approve ||= Orders::WaitingOn.new(person).to_approve.sort_by { |order_request| order_request.submitted_at || order_request.created_at }
    end

    def to_buy
      @to_buy ||= begin
        access = Orders::Access.new(person)
        access.buyer? ? Orders::Reminders.to_buy(access) : []
      end
    end

    # [request, state] for the person's own and followed requests that
    # changed since `since`, newest change first. Their own actions don't
    # count, as no notice tells them of those.
    def changes
      @changes ||= begin
        mine = OrderRequest.where(requested_by_id: person.id)
          .or(OrderRequest.where(id: OrderRequestWatcher.where(person_id: person.id).select(:order_request_id)))
        events = OrderRequestEvent.where(order_request_id: mine.select(:id), action: STATES.keys, created_at: since..)
          .where("actor_id IS DISTINCT FROM ?", person.id).includes(order_request: :team).reorder(created_at: :desc, id: :desc).to_a
        events.select { |event| tells?(event) }.uniq(&:order_request_id).map { |event| [ event.order_request, STATES.fetch(event.action) ] }
      end
    end

    def body
      html = +""
      html << part("Waiting for your approval", to_approve) { |order_request| "#{request_line(order_request)}, asked by #{h(order_request.requested_by.display_name)}" }
      html << part("Ready to buy", to_buy) { |order_request| request_line(order_request) }
      html << part("Your requests", changes) { |(order_request, state)| "#{link_to_request(order_request)}: #{h(state)}" }
      html
    end

    private

    # A step's approval isn't news to the requester (the final one, or one
    # of items approved again, is); an item received is news only once
    # everything has arrived.
    def tells?(event)
      case event.action
      when "approved" then event.field_changes.to_h.dig("status", 1) == "approved" || event.field_changes.to_h.key?("lines")
      when "received" then event.order_request.received? || event.order_request.closed?
      else true
      end
    end

    def part(heading, rows)
      return "" if rows.empty?

      "<h3>#{h(heading)}</h3><ul>#{rows.map { |row| "<li>#{yield(row)}</li>" }.join}</ul>"
    end

    def request_line(order_request)
      needed = order_request.needed_by ? ", needed by #{order_request.needed_by.strftime("%a %b %-d")}" : ""
      "#{link_to_request(order_request)}, #{h(order_request.team.name)}#{h(needed)}"
    end

    def link_to_request(order_request)
      url = Rails.application.routes.url_helpers.orders_request_url(order_request)
      "<a href=\"#{h(url)}\">#{h(order_request.display_title)}</a>"
    end
  end
end
