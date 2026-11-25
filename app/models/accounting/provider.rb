# The interface every accounting source implements. A source is a Gateway
# subclass that calls Gateway.register(self, :accounting) and includes this
# module. The rest of the feature talks to sources only through these
# methods and reads only the neutral columns normalize fills.
module Accounting::Provider
  extend ActiveSupport::Concern

  # What a source can do. Screens and jobs check it; nothing else does.
  CAPABILITIES = %i[ change_feed notifications due_dates pay_links deep_links create_charges create_customers send_charges upload ].freeze

  included do
    has_many :accounting_records, foreign_key: :gateway_id, inverse_of: :gateway, dependent: :delete_all
    has_many :accounting_customer_links, foreign_key: :gateway_id, inverse_of: :gateway, dependent: :delete_all
    has_many :accounting_customer_dismissals, foreign_key: :gateway_id, inverse_of: :gateway, dependent: :delete_all
    has_many :accounting_rules, foreign_key: :gateway_id, inverse_of: :gateway, dependent: :destroy
  end

  # What this source can do, a Set of CAPABILITIES.
  def capabilities = Set.new

  # The name people know the source by ("QuickBooks").
  def source_name = gateway_name

  # The source's own record types, each with the role it normalizes to, or
  # the roles it can normalize to when that depends on the record.
  # e.g. { "Customer" => :customer, "Invoice" => :charge, "LedgerEntry" => %i[ charge payment ] }
  def entity_types = raise NotImplementedError

  # The record types among the category roles that name locations (what
  # location_ids hold) rather than categories (class_ids), e.g. %w[ Department ].
  def location_entity_types = []

  # Yields raw attribute hashes for every record of the type. A full sync
  # marks anything not yielded as deleted.
  def each_record(entity_type) = raise NotImplementedError

  # Turns one raw record into the neutral columns, as a hash. Must be pure:
  # same input, same columns. A source that needs more than one record to
  # compute a column puts what it computed into the raw hash it yields.
  def normalize(entity_type, data) = raise NotImplementedError

  # The external id and version marker of a raw record.
  def external_id(entity_type, data) = raise NotImplementedError
  def revision(entity_type, data) = nil

  # :change_feed -- yields [entity_type, data, deleted?] changed since time.
  def each_change(entity_types, since) = raise NotImplementedError
  # How far back each_change reaches, if limited.
  def change_window = nil

  # :notifications -- one record, after a webhook named it. nil when the
  # source no longer has it.
  def fetch_record(entity_type, external_id) = raise NotImplementedError

  # :create_charges -- creates one charge for a billing line and returns its
  # external id. Safe to call twice with the same line.request_id.
  def create_charge(line) = raise NotImplementedError

  # :create_customers -- creates a customer for a person, returns its external id.
  def create_customer(person, email:, request_id:) = raise NotImplementedError

  # :send_charges -- emails a charge this source created.
  def send_charge(external_id, email:) = raise NotImplementedError

  # How customers are matched to people (Accounting::CustomerLinks::STRATEGIES),
  # in the order tried.
  def match_strategy_list = Accounting::CustomerLinks::DEFAULT_STRATEGIES

  # Whether a sub-customer's records count for the people linked to the
  # customer above it.
  def customer_rollup? = false

  # Called by the sync just before it saves a record (and its hooks fire),
  # for a source that fills a column from records already copied.
  def prepare_record(record) = nil

  # Called by the sync after a batch, with the records it saved, for a
  # source that fills a column from other records once they're all in.
  def after_sync(records) = nil

  # Where the source's connection stands: :ok, :needs_attention or
  # :not_connected.
  def connection_state = :ok

  # Whether the sync jobs should run for this source now.
  def syncable? = connection_state == :ok

  # How often the nightly job reads every record again: :weekly (Sundays),
  # :nightly, or :never for a source whose records only change when someone
  # uploads them.
  def full_sync_cadence = :weekly

  # Writes state the system keeps (last sync, last error) into
  # configuration straight to the row: no gateway hooks or audit log entry
  # every few minutes, and an architect saving the settings meanwhile
  # doesn't lose theirs.
  def record_state!(values)
    values = values.stringify_keys.transform_values { |value| value.respond_to?(:iso8601) ? value.iso8601 : value }
    Gateway.where(id: id).update_all([ "configuration = COALESCE(configuration, '{}'::jsonb) || ?::jsonb", values.to_json ])
    self.configuration = (configuration || {}).merge(values)
    clear_attribute_changes([ :configuration ])
  end

  # A sync didn't finish: keeps the message for the source's page and fires
  # "accounting - sync failed". Records already copied stay as they are.
  def sync_failed!(message)
    record_state!(last_error: message.to_s.truncate(500), last_error_at: Time.current)
    Hook.where(event: "accounting - sync failed").each { |hook| hook.run(self) }
  end

  # A revision for a source whose records carry no version of their own: a
  # digest of the raw data, the same whatever order its keys come in (jsonb
  # doesn't keep the order).
  def content_revision(data)
    Digest::SHA256.hexdigest(canonical(data).to_json)
  end

  def last_full_sync_time = state_time("last_full_sync_at")
  def last_change_check_time = state_time("last_change_check_at")
  def last_error_time = state_time("last_error_at")

  private
    def canonical(value)
      case value
      when Hash then value.to_h { |key, item| [ key.to_s, canonical(item) ] }.sort.to_h
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end

    def state_time(key)
      value = (configuration || {})[key]
      value.present? ? Time.zone.parse(value.to_s) : nil
    rescue ArgumentError
      nil
    end
end
