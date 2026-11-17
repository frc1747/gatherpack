# Order requests: what members ask to have bought, its approval, purchase
# and delivery. This module holds the settings readers, the seams other
# features attach to, and the notifications the models send.
#
# Seams. Register from a config.to_prepare block, as features do with
# GatherPack::Features, so the registrations come back after a development
# reload:
#
#   Rails.application.config.to_prepare do
#     # Fields added to the receive dialog for a line (rendered with the
#     # locals line: and form:), and a callable run with the saved delivery
#     # and the submitted params.
#     Orders.receiving_extensions.register(:my_feature, partial: "my_feature/receive_fields",
#       after_receive: ->(delivery, params) { ... })
#
#     # A picker above the line form on New request (rendered with the
#     # locals order_request: and viewer:). The picker fills the line's
#     # fields itself: each item on the form is a [data-order-line] element
#     # whose fields are named order_request[lines][KEY][field] and carry
#     # data-field="field" (url, description, quantity, vendor_choice,
#     # vendor_part_number, item_type, item_id, ...). item_types: lists the
#     # classes the picker links (item_type is refused for any other), and
#     # attributes: turns a picked record into line attributes for code that
#     # starts a request (OrderRequest.draft_for).
#     Orders.line_entry_extensions.register(:my_feature, partial: "my_feature/line_picker",
#       item_types: [ "MyItem" ], attributes: ->(record) { { description: record.name, item: record } })
#   end
#
# Registering the same key again replaces the earlier entry.
#
# Notifications:
#
#   order_request_changed.gatherpack  order_request:, from:, to: (status names)
#   order_line_received.gatherpack    order_line:, delivery:, quantity:,
#                                     condition: ("good" or the problem
#                                     kind's key), problem_kind: (nil when
#                                     good), person:
module Orders
  # The Setup page heading orders' buttons go under, shared with inventory.
  SETUP_SECTION = "Orders and Inventory".freeze

  # A domain action that isn't allowed in the request's current state, or
  # by this person. The message is fit to show.
  class Refused < StandardError; end

  STATUS_CHANGED_EVENTS = {
    "submitted" => "order_requests - submitted",
    "approved" => "order_requests - approved",
    "declined" => "order_requests - declined"
  }.freeze

  LINE_STATUS_EVENTS = {
    "ordered" => "order_lines - ordered",
    "backordered" => "order_lines - backordered",
    "received" => "order_lines - received",
    "problem" => "order_lines - problem"
  }.freeze

  HOOK_TARGETS = %w[vendors funding_sources order_requests order_lines order_approvals purchases order_deliveries].freeze
  HOOK_EVENTS = (STATUS_CHANGED_EVENTS.values + LINE_STATUS_EVENTS.values).freeze

  class Extensions
    Entry = Struct.new(:key, :partial, :callback, :item_types, keyword_init: true)

    def initialize(callback_name)
      @callback_name = callback_name
      reset!
    end

    def register(key, partial: nil, **options)
      @entries[key.to_sym] = Entry.new(key: key.to_sym, partial: partial, callback: options[@callback_name],
        item_types: Array(options[:item_types]).map(&:to_s))
    end

    def unregister(key)
      @entries.delete(key.to_sym)
    end

    def all
      @entries.values
    end

    def any?
      @entries.any?
    end

    def reset!
      @entries = {}
    end
  end

  def self.receiving_extensions
    @receiving_extensions ||= Extensions.new(:after_receive)
  end

  def self.line_entry_extensions
    @line_entry_extensions ||= Extensions.new(:attributes)
  end

  # The classes a line entry extension may link a line to (item_type).
  def self.line_item_types
    line_entry_extensions.all.flat_map(&:item_types).uniq
  end

  def self.enabled?
    GatherPack::Features.enabled?(:orders)
  end

  # Runs every receiving extension's callback for a saved delivery.
  def self.after_receive(delivery, params = {})
    receiving_extensions.all.each { |entry| entry.callback&.call(delivery, params) }
  end

  def self.request_changed(order_request, from, to)
    ActiveSupport::Notifications.instrument("order_request_changed.gatherpack", order_request: order_request, from: from, to: to)
  end

  def self.line_received(delivery)
    ActiveSupport::Notifications.instrument("order_line_received.gatherpack",
      order_line: delivery.order_line, delivery: delivery, quantity: delivery.quantity,
      condition: delivery.condition, problem_kind: delivery.delivery_problem_kind, person: delivery.received_by)
  end

  def self.run_hooks(event, record)
    Hook.where(event: event).each { |hook| hook.run(record) }
  end
end
