module Orders
  # Buyers' screens (spec §3.4, §3.5): the To buy queue, recording a
  # purchase, and the purchases themselves. Someone who sees a purchase
  # only through one of its requests gets its vendor, date and status, and
  # their own items.
  class PurchasesController < BaseController
    PURCHASE_FIELDS = %i[vendor_order_number ordered_on expected_on tracking_url shipping tax paid_with note].freeze

    before_action :set_purchase, only: %i[show edit update make_vendor]

    # GET /orders/purchases
    # mine=1 limits them to the viewer's own purchases.
    def index
      authorize Purchase
      @purchases = policy_scope(Purchase).includes(:vendor, :buyer, order_lines: :order_request)
        .order(Purchase.arel_table[:ordered_on].desc.nulls_last, created_at: :desc)
      @purchases = @purchases.where(buyer: current_user.person) if params[:mine].present?
      @purchases = @purchases.where(ledger_entry_id: nil) if params[:not_in_ledger].present? && Orders::LedgerRecording.ledger_on?
      @purchases = @purchases.page(params[:page])
    end

    # GET /orders/purchases/1
    def show
      purchase_policy = policy(@purchase)
      @full = purchase_policy.full?
      @lines = purchase_policy.visible_lines.sort_by { |line| [ line.order_request.display_title, line.position.to_i ] }
    end

    # GET /orders/purchases/to_buy
    def to_buy
      authorize Purchase, :create?
      @groups = Orders::ToBuy.new(current_user.person).groups
    end

    # GET /orders/purchases/new?line_ids[]=…
    def new
      authorize Purchase, :create?
      @group = Orders::ToBuy.new(current_user.person).selection(params[:line_ids])
      @purchase = Purchase.new(ordered_on: Date.current, paid_with: paid_with_labels.first)
    end

    # POST /orders/purchases
    def create
      authorize Purchase, :create?
      @group = Orders::ToBuy.new(current_user.person).selection(params[:line_ids])
      @purchase = Purchase.new(purchase_attributes)
      vendor, other_vendor_name = chosen_vendor
      ledger = ledger_choice
      purchase = Orders::RecordPurchase.new(buyer: current_user.person, lines: @group.lines, vendor: vendor,
        other_vendor_name: other_vendor_name, prices: line_prices, attributes: purchase_attributes,
        receipts: params.dig(:purchase, :receipts)).call
      notice = recorded_notice(purchase)
      if ledger
        # After the purchase commits, so its receipts are stored and can be
        # copied to the entry.
        begin
          Orders::RecordInLedger.new(purchase, ledger: ledger, by: current_user.person).call
        rescue Orders::Refused => e
          return redirect_to orders_purchase_path(purchase), notice: notice, alert: e.message
        end
      end
      redirect_to orders_purchase_path(purchase), notice: notice
    rescue ActiveRecord::RecordInvalid => e
      prefix = e.record.is_a?(OrderLine) ? "#{e.record.display_name}: " : ""
      @errors = e.record.errors.full_messages.map { |message| prefix + message }
      render :new, status: :unprocessable_content
    end

    # GET /orders/purchases/1/edit
    def edit
    end

    # PATCH /orders/purchases/1
    def update
      if Orders::UpdatePurchase.new(@purchase, purchase_attributes, by: current_user.person,
          receipts: params.dig(:purchase, :receipts)).call
        redirect_to orders_purchase_path(@purchase), notice: "Order updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    # POST /orders/purchases/1/make_vendor
    # Turns the purchase's "Other store" name into a vendor record.
    def make_vendor
      authorize Vendor, :create?
      vendor = Orders::VendorFromPurchase.new(@purchase, by: current_user.person).call
      redirect_to orders_purchase_path(@purchase), notice: "#{vendor.name} is now a vendor."
    end

    private

    def set_purchase
      @purchase = policy_scope(Purchase).includes(:vendor, :buyer, order_lines: [ :vendor, { order_request: :team } ])
        .find(params[:id])
      authorize @purchase, action_name == "make_vendor" ? :update? : nil
    end

    def purchase_attributes
      attributes = params.fetch(:purchase, {}).permit(*PURCHASE_FIELDS).to_h
      %w[shipping tax].each { |field| attributes[field] = "0" if attributes.key?(field) && attributes[field].blank? }
      attributes.delete("paid_with") if attributes.key?("paid_with") && !attributes["paid_with"].in?(paid_with_labels)
      if attributes.key?("paid_with")
        choice = Orders::Config.paid_with.find { |option| option.label == attributes["paid_with"] }
        # Whoever paid with their own card is the buyer, not whoever edits it later.
        attributes["reimburse_to_id"] = choice.reimburse ? (@purchase&.buyer_id || current_user.person.id) : nil
      end
      attributes
    end

    # The vendor for the ticked items: their own, or for "Not sure" items the
    # one the buyer names here.
    def chosen_vendor
      case @group.key
      when :vendor then [ @group.vendor, nil ]
      when :other then [ nil, @group.other_vendor_name ]
      else
        vendor_id = params.dig(:purchase, :vendor_id).presence
        vendor_id ? [ policy_scope(Vendor).active.find(vendor_id), nil ] : [ nil, params.dig(:purchase, :other_vendor_name) ]
      end
    end

    # { line id => cents } for the prices typed in; a blank one keeps the
    # estimate.
    def line_prices
      params.fetch(:prices, {}).permit(@group.lines.map(&:id)).to_h.filter_map do |line_id, text|
        [ line_id, Monetize.parse(text).cents ] if text.present?
      end.to_h
    end

    # The ledger to record the purchase in, when Record in ledger is ticked
    # (spec §6). Checked before anything is recorded, so a ledger the buyer
    # can't add to refuses the purchase too.
    def ledger_choice
      return unless params[:record_in_ledger] == "1" && Orders::LedgerRecording.ledger_on?

      ledger = Ledger.find_by(id: params[:ledger_id])
      Orders::RecordInLedger.check!(ledger: ledger, by: current_user.person)
      ledger
    end

    def paid_with_labels
      Orders::Config.paid_with.map(&:label)
    end

    def recorded_notice(purchase)
      waiting = purchase.order_lines.reload.count(&:needs_reapproval?)
      return "Purchase recorded." if waiting.zero?

      "Purchase recorded. #{waiting} #{waiting == 1 ? 'item costs' : 'items cost'} more than was approved, " \
        "so #{waiting == 1 ? 'it needs' : 'they need'} re-approval."
    end
  end
end
