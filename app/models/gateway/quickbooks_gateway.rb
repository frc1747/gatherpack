# QuickBooks Online as an accounting source: copies customers, invoices,
# payments and credits and keeps the copy current through change data
# capture and webhooks. Read only: see Accounting::Quickbooks::Client for
# what GatherPack may do in QuickBooks.
class Gateway::QuickbooksGateway < Gateway
  Gateway.register(self, :accounting)
  include Accounting::Provider

  # QuickBooks record types and the role each becomes.
  ENTITY_ROLES = {
    "Customer" => :customer,
    "Invoice" => :charge,
    "SalesReceipt" => :receipt,
    "Payment" => :payment,
    "CreditMemo" => :credit,
    "RefundReceipt" => :refund,
    "Item" => :item,
    "Class" => :category,
    "Department" => :category
  }.freeze
  DEFAULT_ENTITIES = %w[ Customer Invoice Payment CreditMemo Item ].freeze
  # Types that can be made inactive; their queries ask for inactive ones too.
  WITH_ACTIVE = %w[ Customer Item Class Department ].freeze
  ENVIRONMENTS = %w[ sandbox production ].freeze
  ROLLUPS = %w[ none parent ].freeze
  STATUSES = %w[ not_connected connected needs_reconnect disconnected ].freeze
  DEFAULT_ROLE_LABELS = { "charge" => "Invoice", "receipt" => "Receipt", "payment" => "Payment", "credit" => "Credit", "refund" => "Refund" }.freeze
  # How long before the sign-in runs out the page asks for a reconnect.
  RECONNECT_WARNING = 30.days

  store_accessor :secrets, :client_secret, :webhook_verifier_token
  store_accessor :configuration, :client_id, :environment, :synced_entities, :customer_rollup,
                 :match_strategies, :match_field_path, :role_labels
  store_accessor :configuration, :realm_id, :company_name, :connection_status, :last_change_check_at,
                 :last_full_sync_at, :last_error, :calls_this_month, :calls_month

  has_one :accounting_credential, foreign_key: :gateway_id, inverse_of: :gateway, dependent: :delete

  validates :environment, inclusion: { in: ENVIRONMENTS }
  validate :synced_entities_known
  validates :customer_rollup, inclusion: { in: ROLLUPS, message: "is none or parent" }, allow_blank: true
  validate :match_strategies_known

  def fields
    [ :client_id, :client_secret, :environment, :webhook_verifier_token, :synced_entities, :customer_rollup, :match_strategies, :match_field_path ]
  end

  def self.webhook_headers
    [ "HTTP_INTUIT_SIGNATURE" ]
  end

  def identifier_icon
    "file-invoice-dollar"
  end

  def source_name
    "QuickBooks"
  end

  def environment
    super.presence || "sandbox"
  end

  def connection_status
    super.presence || "not_connected"
  end

  # The synced types, in a fixed order.
  def synced_entity_list
    chosen = (synced_entities.presence || DEFAULT_ENTITIES.join(" ")).to_s.split(/[\s,]+/)
    ENTITY_ROLES.keys & chosen
  end

  def role_label(role)
    (role_labels.presence || {}).fetch(role.to_s, nil).presence || DEFAULT_ROLE_LABELS.fetch(role.to_s)
  end

  def client
    @client ||= Accounting::Quickbooks::Client.new(self)
  end

  def connected?
    connection_status == "connected" && accounting_credential.present?
  end

  # Calls to QuickBooks' API this calendar month.
  def calls_in_month
    calls_month == Time.current.strftime("%Y-%m") ? calls_this_month.to_i : 0
  end

  # Counts one API call, straight to the row so jobs running at once don't
  # lose counts.
  def record_call!
    month = Time.current.strftime("%Y-%m")
    Gateway.where(id: id).update_all([ <<~SQL.squish, month, month ])
      configuration = COALESCE(configuration, '{}'::jsonb) || jsonb_build_object('calls_month', ?::text, 'calls_this_month',
        CASE WHEN configuration->>'calls_month' = ? THEN COALESCE((configuration->>'calls_this_month')::integer, 0) + 1 ELSE 1 END)
    SQL
  end

  # QuickBooks refused the sign-in: syncing stops until someone reconnects.
  def needs_reconnect!(message)
    record_state!(connection_status: "needs_reconnect")
    sync_failed!(message)
  end

  # When the sign-in runs out unless someone reconnects first, when that's
  # within RECONNECT_WARNING.
  def reconnect_by
    expires = accounting_credential&.refresh_token_expires_at
    expires if expires && connected? && expires <= RECONNECT_WARNING.from_now
  end

  # Buttons on the gateway page (architects only, who may also open
  # Records). Customers (admins only) and Disconnect are in the details
  # partial; Sync now and Copy everything again are on the Records page.
  def routes
    helpers = Rails.application.routes.url_helpers
    links = []
    if self.class.encryption_ready? && client_id.present? && client_secret.present?
      links << { name: realm_id.present? ? "Reconnect" : "Connect to QuickBooks", path: helpers.connect_accounting_connection_path(self) }
    end
    links << { name: "Records", path: helpers.accounting_connection_records_path(self) }
  end

  # Tokens are stored encrypted, so connecting needs the encryption keys.
  def self.encryption_ready?
    ActiveRecord::Encryption.config.primary_key.present?
  rescue ActiveRecord::Encryption::Errors::Configuration
    false
  end

  def webhook_problem
    "aren't accepted until the verifier token from the Intuit app is set; the changes job still checks every 15 minutes" if webhook_verifier_token.blank?
  end

  # Intuit signs each notification with the verifier token: a base64
  # HMAC-SHA256 of the raw body in the intuit-signature header.
  def verify_webhook(payload, headers)
    return false unless Accounting.enabled?

    signature = headers["HTTP_INTUIT_SIGNATURE"].to_s
    return false if webhook_verifier_token.blank? || signature.blank?

    expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", webhook_verifier_token, payload))
    ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end

  # Notifications are CloudEvents carrying ids only: each named record is
  # fetched, except deletes, which are marked at once.
  def handle_webhook(payload, headers)
    return unless Accounting.enabled? && connected?

    events = JSON.parse(payload)
    Array.wrap(events).each do |event|
      next unless event.is_a?(Hash) && event["intuitaccountid"].to_s == realm_id.to_s

      _, entity, operation = event["type"].to_s.split(".")
      entity_type = entity_types.keys.find { |name| name.downcase == entity.to_s.downcase }
      external_id = event["intuitentityid"].to_s
      next if entity_type.nil? || external_id.blank?

      if operation == "deleted"
        Accounting::Sync.new(self).delete(entity_type, [ external_id ])
      else
        Accounting::FetchRecordJob.perform_later(self, entity_type, external_id)
      end
    end
  end

  # -- Accounting::Provider --

  def capabilities
    found = Set.new(%i[ change_feed due_dates pay_links deep_links ])
    found << :notifications if webhook_verifier_token.present?
    found
  end

  def connection_state
    case connection_status
    when "connected" then accounting_credential.present? ? :ok : :not_connected
    when "needs_reconnect" then :needs_attention
    else :not_connected
    end
  end

  def entity_types
    ENTITY_ROLES.slice(*synced_entity_list)
  end

  # Classes are categories (ClassRef); departments are locations (DepartmentRef).
  def location_entity_types
    %w[ Department ]
  end

  def each_record(entity_type, &block)
    client.query(entity_type, where: ("Active IN (true, false)" if WITH_ACTIVE.include?(entity_type)), &block)
  end

  def normalize(entity_type, data)
    normalizer.normalize(entity_type, data)
  end

  def external_id(entity_type, data)
    data["Id"].to_s
  end

  def revision(entity_type, data)
    data["SyncToken"]&.to_s
  end

  def each_change(entity_types, since, &block)
    client.changes(entity_types, since, &block)
  end

  def change_window
    30.days
  end

  def fetch_record(entity_type, external_id)
    client.get(entity_type, external_id)
  end

  # match_strategies: some of reference, name and email, in the order tried.
  def match_strategy_list
    chosen = match_strategies.to_s.split(/[\s,]+/).compact_blank.uniq & Accounting::CustomerLinks::STRATEGIES
    chosen.presence || Accounting::CustomerLinks::DEFAULT_STRATEGIES
  end

  def customer_rollup?
    customer_rollup.to_s == "parent"
  end

  def prepare_record(record)
    record.applied_to = Accounting::Quickbooks::CreditApplications.new(self).applied_to_for(record) if record.entity_type == "CreditMemo"
  end

  def after_sync(records)
    Accounting::Quickbooks::CreditApplications.new(self).resolve(records)
  end

  private
    def normalizer
      Accounting::Quickbooks::Normalizer.new(
        app_host: Accounting::Quickbooks::APP_HOSTS.fetch(environment),
        labels: DEFAULT_ROLE_LABELS.keys.index_with { |role| role_label(role) },
        match_field_path: match_field_path
      )
    end

    def synced_entities_known
      return if synced_entities.blank?

      unknown = synced_entities.to_s.split(/[\s,]+/).compact_blank - ENTITY_ROLES.keys
      errors.add(:synced_entities, "has types QuickBooks sources don't copy: #{unknown.join(', ')}") if unknown.any?
    end

    def match_strategies_known
      unknown = match_strategies.to_s.split(/[\s,]+/).compact_blank - Accounting::CustomerLinks::STRATEGIES
      errors.add(:match_strategies, "can only be reference, name and email: #{unknown.join(', ')} isn't one") if unknown.any?
    end
end
