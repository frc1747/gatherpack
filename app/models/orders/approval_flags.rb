# What the approve screen marks for an approver to check (spec §3.3):
# items from a store that isn't preferred, from another store, or with no
# store chosen; items without a link or part number, or without a price; a
# request with no purpose, one needed soon or already past, and one with
# no funding source. The funding picture (restriction, what would remain,
# dates) is shown beside these on the request page.
#
# Works on loaded lines and vendors, so the To approve list can flag many
# requests without a query each.
module Orders
  class ApprovalFlags
    Flag = Struct.new(:key, :text, :line, keyword_init: true)

    # A needed_by this close counts as soon: the same 3 days as the
    # needed-by notice (spec §3.11). Vendors carry no lead time.
    SOON_DAYS = 3

    include Enumerable

    attr_reader :order_request

    def initialize(order_request, today: Date.current)
      @order_request = order_request
      @today = today
    end

    def each(&block)
      all.each(&block)
    end

    def all
      @all ||= request_flags + order_request.live_lines.flat_map { |line| line_flags(line) }
    end

    def request_flags
      flags = []
      flags << Flag.new(key: :no_purpose, text: "No reason given") if order_request.purpose.blank?
      needed_by = order_request.needed_by
      if needed_by && needed_by < @today
        flags << Flag.new(key: :past, text: "Needed by #{I18n.l(needed_by, format: :short)}, which has passed")
      elsif needed_by && needed_by <= @today + SOON_DAYS
        flags << Flag.new(key: :soon, text: "Needed by #{I18n.l(needed_by, format: :short)}")
      end
      if order_request.live_lines.any? { |line| line.effective_funding_source_id.nil? }
        flags << Flag.new(key: :no_funding, text: "No funding source")
      end
      flags
    end

    def line_flags(line)
      flags = []
      case line.vendor_choice
      when :not_sure
        flags << Flag.new(key: :not_sure, text: "Store not chosen", line: line)
      when :other
        flags << Flag.new(key: :other_store, text: "Other store: #{line.other_vendor_name}", line: line)
      else
        flags << Flag.new(key: :not_preferred, text: "#{line.vendor.name} isn't a preferred store", line: line) unless line.vendor.preferred?
      end
      if line.url.blank? && line.vendor_part_number.blank? && line.manufacturer_part_number.blank?
        flags << Flag.new(key: :no_link, text: "No link or part number", line: line)
      end
      flags << Flag.new(key: :no_price, text: "No price", line: line) if line.unit_price_cents.nil?
      flags
    end
  end
end
