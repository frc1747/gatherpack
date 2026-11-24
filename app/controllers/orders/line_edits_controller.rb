module Orders
  class LineEditsController < BaseController
    TEXT_FIELDS = %i[
      description manufacturer manufacturer_part_number vendor_part_number url unit other_vendor_name
      other_vendor_reason note
    ].freeze

    # PATCH /orders/requests/1/line_edits/2
    # An approver fixes an item before deciding (spec §3.3): a part number,
    # a lower quantity, the store or the price. The edit goes through
    # OrderRequest#edit_line!, so it shows in the timeline, and a material
    # change clears earlier approvals.
    def update
      @order_request = authorize policy_scope(OrderRequest).find(params[:request_id]), :approver_edit?
      line = @order_request.order_lines.find(params[:id])
      @order_request.edit_line!(line, line_attributes(line), by: current_user.person)
      redirect_to orders_request_path(@order_request, anchor: "decision"), notice: "Item saved."
    rescue ActiveRecord::RecordInvalid => error
      redirect_to orders_request_path(@order_request, anchor: "decision"), alert: error.record.errors.full_messages.to_sentence
    end

    private

    # Only the fields the approver changed. Values are compared after
    # trimming and turning blanks into nil, so a box left as it was isn't a
    # change (nil to "", or "Wheel " to "Wheel") that could clear approvals.
    def line_attributes(line)
      values = params.require(:line).permit(*TEXT_FIELDS, :quantity, :units_per, :estimated_unit_price, :store, :funding_source_id)
      attributes = TEXT_FIELDS.index_with { |field| values[field].to_s.strip.presence }
      attributes[:quantity] = values[:quantity].presence&.to_i
      attributes[:units_per] = values[:units_per].presence&.to_i
      attributes[:estimated_unit_price_cents] = price_cents(values[:estimated_unit_price])
      attributes.merge!(store(values[:store], attributes[:other_vendor_name]))
      if policy(@order_request).set_funding?
        attributes[:funding_source_id] = values[:funding_source_id].presence && policy_scope(FundingSource).find(values[:funding_source_id]).id
      end
      attributes.reject { |field, value| normalized(value) == normalized(line[field]) }
    end

    def normalized(value)
      value.is_a?(String) ? value.strip.presence : value
    end

    # "Where from?": a vendor, "other" with a typed name, or blank for not
    # sure.
    def store(choice, other_name)
      case choice.to_s
      when "" then { vendor_id: nil, other_vendor_name: nil }
      when "other" then { vendor_id: nil, other_vendor_name: other_name }
      else { vendor_id: Vendor.find(choice).id, other_vendor_name: nil }
      end
    end

    def price_cents(value)
      return nil if value.blank?

      (BigDecimal(value.to_s.delete("$,").strip) * 100).round
    rescue ArgumentError
      raise Orders::Refused, "Enter the price as a number, like 12.50."
    end
  end
end
