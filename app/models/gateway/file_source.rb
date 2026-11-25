# An uploaded spreadsheet as an accounting source, for a group that exports
# from its accounting program or keeps a sheet by hand. An admin uploads a
# CSV (Accounting::Files::Template), checks the preview and applies it; the
# records then match the file, and rows missing from it are marked deleted.
# Nothing is fetched from anywhere.
class Gateway::FileSource < Gateway
  Gateway.register(self, :accounting)
  include Accounting::Provider

  # The file's roles are its entity types; customers and items come from
  # the distinct values in their columns.
  ENTITY_ROLES = {
    "customer" => :customer, "item" => :item, "charge" => :charge, "receipt" => :receipt,
    "payment" => :payment, "credit" => :credit, "refund" => :refund
  }.freeze
  DEFAULT_ROLE_LABELS = { "charge" => "Charge", "receipt" => "Receipt", "payment" => "Payment", "credit" => "Credit", "refund" => "Refund" }.freeze
  # A customer cell that's a GatherPack person id or an email address.
  REFERENCE = /\A(per_[a-z0-9]+|[^@\s]+@[^@\s]+\.[^@\s]+)\z/i

  store_accessor :configuration, :role_labels
  store_accessor :configuration, :last_change_check_at, :last_full_sync_at, :last_error

  has_many :accounting_uploads, foreign_key: :gateway_id, inverse_of: :gateway, dependent: :delete_all

  def fields
    []
  end

  def identifier_icon
    "file-csv"
  end

  def source_name
    "the file"
  end

  def role_label(role)
    (role_labels.presence || {}).fetch(role.to_s, nil).presence || DEFAULT_ROLE_LABELS.fetch(role.to_s)
  end

  # The upload the records come from: the one being applied, else the last
  # one applied.
  def current_upload
    @applying || accounting_uploads.applied.order(applied_at: :desc).first
  end

  # Reads the records from upload while the block runs (Accounting::ApplyUploadJob).
  def with_upload(upload)
    @applying = upload
    yield
  ensure
    @applying = nil
  end

  def routes
    helpers = Rails.application.routes.url_helpers
    [
      { name: "Upload", path: helpers.new_accounting_connection_upload_path(self) },
      { name: "Records", path: helpers.accounting_connection_records_path(self) }
    ]
  end

  # -- Accounting::Provider --

  def capabilities
    Set.new(%i[ due_dates upload ])
  end

  def entity_types
    ENTITY_ROLES
  end

  def each_record(entity_type, &block)
    Array((current_upload&.parsed_records || {})[entity_type]).each(&block)
  end

  def normalize(entity_type, data)
    case entity_type
    when "customer" then normalize_customer(data)
    when "item" then { role: "item", name: data["name"], active: true }
    else normalize_transaction(entity_type, data)
    end
  end

  def external_id(entity_type, data)
    data["id"].to_s
  end

  def revision(entity_type, data)
    content_revision(data)
  end

  # A person id or an account email in the customer column links
  # automatically; names go through suggestions.
  def match_strategy_list
    %w[ reference name email ]
  end

  def full_sync_cadence
    :never
  end

  private
    # The reference is the lowercased cell (the customer's id), so a
    # spreadsheet's "Per_…" still matches a person id.
    def normalize_customer(data)
      label = data["label"].to_s
      reference = data["id"].to_s if label.match?(REFERENCE)
      { role: "customer", customer_external_id: data["id"], name: label, active: true,
        email: (label if reference && label.include?("@")), reference: reference }
    end

    def normalize_transaction(role, data)
      total = data["total_cents"].to_i
      item = data["item"]
      columns = {
        role: role, customer_external_id: data["customer"], number: data["number"],
        txn_date: date(data["date"]), total_cents: total, description: data["description"],
        lines: [ { "item_id" => item, "class_id" => nil, "amount_cents" => total } ], item_ids: [ item ].compact,
        public_label: label(role, data)
      }

      case role
      when "charge", "receipt"
        columns.merge(due_on: (date(data["due_date"]) if role == "charge"), balance_cents: data["balance_cents"].to_i)
      when "payment", "credit"
        unapplied = data["unapplied_cents"].to_i
        columns.merge(applied_to: Array(data["applied_to"]), unapplied_cents: unapplied, balance_cents: (unapplied if role == "credit"))
      else
        columns.merge(applied_to: Array(data["applied_to"]))
      end
    end

    # The role's word, and for charges and receipts the number and item.
    # Never the description, and credits never name an item.
    def label(role, data)
      return role_label(role) unless role.in?(%w[ charge receipt ])

      [ [ role_label(role), data["number"] ].compact.join(" "), data["item_name"].presence ].compact.join(" · ")
    end

    def date(text)
      text.present? ? Date.iso8601(text) : nil
    end
end
