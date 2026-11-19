# The To buy queue for one buyer (spec §3.4): the approved, unbought items
# Orders::WaitingOn counts for them, grouped by vendor. Items with vendor
# "Not sure" come first, as "Vendor not chosen"; the other groups follow by
# their oldest needed-by date, with no date last.
#
#   to_buy = Orders::ToBuy.new(person)
#   to_buy.groups               # Group structs
#   to_buy.selection(line_ids)  # the Group holding exactly those items
module Orders
  class ToBuy
    Group = Struct.new(:key, :vendor, :other_vendor_name, :lines, keyword_init: true) do
      def not_sure?
        key == :not_sure
      end

      def name
        vendor&.name || other_vendor_name || "Vendor not chosen"
      end

      def earliest_needed_by
        lines.filter_map { |line| line.order_request.needed_by }.min
      end

      def total_cents
        lines.sum(&:cost_cents)
      end
    end

    attr_reader :person

    def initialize(person)
      @person = person
    end

    def lines
      @lines ||= Orders::WaitingOn.for(person).buy_lines
        .includes(:vendor, :funding_source, order_request: %i[team requested_by funding_source])
        .to_a
    end

    def groups
      @groups ||= lines.group_by { |line| group_key(line) }.map do |key, members|
        Group.new(key: key.first, vendor: members.first.vendor,
          other_vendor_name: key.first == :other ? members.first.other_vendor_name : nil,
          lines: members.sort_by { |line| line_order(line) })
      end.sort_by { |group| group_order(group) }
    end

    # The group holding the given items, refused unless every one of them is
    # still waiting for this buyer and they're all from one vendor.
    def selection(line_ids)
      ids = Array(line_ids).compact_blank.map(&:to_s).uniq
      raise Orders::Refused, "Tick at least one item." if ids.empty?

      chosen = lines.select { |line| ids.include?(line.id) }
      raise Orders::Refused, "Some of those items are no longer waiting for a buyer." if chosen.size != ids.size

      keys = chosen.map { |line| group_key(line) }.uniq
      raise Orders::Refused, "Tick items from one vendor." if keys.size > 1

      group = groups.find { |candidate| group_key(candidate.lines.first) == keys.first }
      Group.new(**group.to_h.merge(lines: group.lines.select { |line| ids.include?(line.id) }))
    end

    private

    def group_key(line)
      case line.vendor_choice
      when :vendor then [ :vendor, line.vendor_id ]
      when :other then [ :other, line.other_vendor_name.downcase.squish ]
      else [ :not_sure ]
      end
    end

    def line_order(line)
      needed_by = line.order_request.needed_by
      [ needed_by ? 0 : 1, needed_by || Date.new(0), line.order_request.approved_at || Time.at(0), line.order_request_id, line.position.to_i ]
    end

    def group_order(group)
      earliest = group.earliest_needed_by
      [ group.not_sure? ? 0 : 1, earliest ? 0 : 1, earliest || Date.new(0), group.name.downcase ]
    end
  end
end
