# Turns a QuickBooks record into AccountingRecord's neutral columns. With
# Accounting::Quickbooks::CreditApplications, the only code that knows
# QuickBooks' field names. Pure: the same record always gives the same
# columns.
class Accounting::Quickbooks::Normalizer
  # Where each type's record opens in QuickBooks: page and id parameter.
  DEEP_LINKS = {
    "Customer" => [ "customerdetail", "nameId" ],
    "Invoice" => [ "invoice", "txnId" ],
    "SalesReceipt" => [ "salesreceipt", "txnId" ],
    "Payment" => [ "recvpayment", "txnId" ],
    "CreditMemo" => [ "creditmemo", "txnId" ],
    "RefundReceipt" => [ "refundreceipt", "txnId" ]
  }.freeze

  # labels: role => word for public_label ("charge" => "Invoice").
  def initialize(app_host:, labels:, match_field_path: nil)
    @app_host = app_host
    @labels = labels
    @match_field_path = match_field_path.to_s.split(".").compact_blank
  end

  def normalize(entity_type, data)
    columns =
      case entity_type
      when "Customer" then customer(data)
      when "Invoice" then invoice(data)
      when "SalesReceipt" then sales_receipt(data)
      when "Payment" then payment(data)
      when "CreditMemo" then credit_memo(data)
      when "RefundReceipt" then refund_receipt(data)
      when "Item" then { role: "item", name: data["Name"], active: data["Active"] != false }
      when "Class", "Department" then { role: "category", name: data["Name"], active: data["Active"] != false }
      else { role: "other" }
      end

    columns.merge(external_url: deep_link(entity_type, data["Id"]), external_updated_at: time(data.dig("MetaData", "LastUpdatedTime")))
  end

  # A payment's lines that name a transaction of the type, as
  # [[external id, cents]].
  def self.linked(data, txn_type)
    Array(data["Line"]).flat_map do |line|
      Array(line["LinkedTxn"]).select { |txn| txn["TxnType"] == txn_type }.map { |txn| [ txn["TxnId"].to_s, cents(line["Amount"]) ] }
    end
  end

  # How a payment's money reaches its invoices. QuickBooks records a credit
  # memo's use on a payment too: its invoice lines add up the money and the
  # credits applied together. The money (total less unapplied) goes to the
  # invoices first; returns [what the money paid, what's left of each
  # invoice line for credits], both as [[external id, cents]].
  def self.allocate_payment(data)
    money = cents(data["TotalAmt"]).to_i - cents(data["UnappliedAmt"]).to_i
    paid = []
    left = []
    linked(data, "Invoice").each do |id, amount|
      use = [ amount.to_i, [ money, 0 ].max ].min
      money -= use
      paid << [ id, use ] if use.positive?
      left << [ id, amount.to_i - use ] if amount.to_i > use
    end
    [ paid, left ]
  end

  def self.cents(value)
    return nil if value.nil?

    (BigDecimal(value.to_s) * 100).round.to_i
  end

  private
    def customer(data)
      {
        role: "customer",
        customer_external_id: data["Id"].to_s,
        parent_external_id: data.dig("ParentRef", "value"),
        name: data["DisplayName"],
        email: data.dig("PrimaryEmailAddr", "Address"),
        reference: reference(data),
        active: data["Active"] != false
      }
    end

    def invoice(data)
      lines = lines(data)
      transaction(data).merge(
        role: "charge",
        due_on: date(data["DueDate"]),
        balance_cents: cents(data["Balance"]),
        lines: lines,
        item_ids: lines.filter_map { |line| line["item_id"] }.uniq,
        class_ids: ([ data.dig("ClassRef", "value") ] + lines.map { |line| line["class_id"] }).compact.uniq,
        location_ids: [ data.dig("DepartmentRef", "value") ].compact,
        pay_url: data["InvoiceLink"].presence,
        public_label: charge_label(data),
        description: description(data)
      )
    end

    def sales_receipt(data)
      invoice(data).merge(role: "receipt", due_on: nil, balance_cents: 0, pay_url: nil,
        public_label: [ label("receipt"), data["DocNumber"].presence ].compact.join(" "))
    end

    def payment(data)
      paid, = self.class.allocate_payment(data)
      transaction(data).merge(
        role: "payment",
        number: data["PaymentRefNum"].presence,
        applied_to: paid.map { |id, amount| { "external_id" => id, "amount_cents" => amount } },
        unapplied_cents: cents(data["UnappliedAmt"]) || 0,
        public_label: label("payment"),
        description: description(data)
      )
    end

    # applied_to is filled after a sync from the payments that apply the
    # credit (CreditApplications).
    def credit_memo(data)
      transaction(data).merge(
        role: "credit",
        balance_cents: cents(data["Balance"]),
        unapplied_cents: cents(data["Balance"]),
        public_label: label("credit"),
        description: description(data)
      )
    end

    def refund_receipt(data)
      transaction(data).merge(role: "refund", public_label: label("refund"), description: description(data))
    end

    def transaction(data)
      {
        customer_external_id: data.dig("CustomerRef", "value"),
        number: data["DocNumber"].presence,
        txn_date: date(data["TxnDate"]),
        total_cents: cents(data["TotalAmt"]),
        voided: voided?(data)
      }
    end

    # Sales lines, including those inside groups (bundles).
    def lines(data)
      Array(data["Line"]).flat_map do |line|
        case line["DetailType"]
        when "SalesItemLineDetail" then [ sales_line(line) ]
        when "GroupLineDetail" then Array(line.dig("GroupLineDetail", "Line")).select { |inner| inner["DetailType"] == "SalesItemLineDetail" }.map { |inner| sales_line(inner) }
        else []
        end
      end
    end

    def sales_line(line)
      detail = line["SalesItemLineDetail"] || {}
      { "item_id" => detail.dig("ItemRef", "value"), "class_id" => detail.dig("ClassRef", "value"), "amount_cents" => cents(line["Amount"]) }
    end

    # "Invoice 1042 · Dues", "Invoice 1042 · Dues and 2 more". Item names
    # only: never a memo or note.
    def charge_label(data)
      names = Array(data["Line"]).flat_map do |line|
        case line["DetailType"]
        when "SalesItemLineDetail" then [ line.dig("SalesItemLineDetail", "ItemRef", "name") ]
        when "GroupLineDetail" then [ line.dig("GroupLineDetail", "GroupItemRef", "name") ]
        else []
        end
      end.compact_blank.uniq

      title = [ label("charge"), data["DocNumber"].presence ].compact.join(" ")
      return title if names.empty?

      more = names.size > 1 ? " and #{names.size - 1} more" : ""
      "#{title} · #{names.first}#{more}"
    end

    # QuickBooks keeps a voided transaction with its amounts zeroed and
    # "Voided" at the start of its private note.
    def voided?(data)
      data["PrivateNote"].to_s.start_with?("Voided") && cents(data["TotalAmt"]).to_i.zero?
    end

    def description(data)
      [ data["PrivateNote"], data.dig("CustomerMemo", "value") ].compact_blank.join("\n").presence
    end

    def reference(data)
      return nil if @match_field_path.empty?

      value = data.dig(*@match_field_path)
      value.is_a?(Hash) || value.is_a?(Array) ? nil : value&.to_s&.strip.presence
    end

    def label(role)
      @labels.fetch(role.to_s)
    end

    def deep_link(entity_type, id)
      page, param = DEEP_LINKS[entity_type]
      return nil unless page && id.present?

      "#{@app_host}/app/#{page}?#{param}=#{CGI.escape(id.to_s)}"
    end

    def cents(value)
      self.class.cents(value)
    end

    def date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    def time(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end
end
