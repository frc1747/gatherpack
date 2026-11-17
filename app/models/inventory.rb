# Inventory: items, nested locations, stock movements and tracked units.
# This module holds the settings readers' entry points, the seams other
# features attach to, and the notifications and hooks the models send.
#
# Seams. Register from a config.to_prepare block, as features do with
# GatherPack::Features, so the registrations come back after a development
# reload:
#
#   Rails.application.config.to_prepare do
#     # A button on the reorder list. path is called with the ticked rows,
#     # [[item, quantity], ...], and returns where to go; visible with the
#     # viewing person. The list submits as a POST with a CSRF token; only an
#     # action that changes nothing (a printout, a download) may declare
#     # method: :get, which also lets it run from a GET.
#     Inventory.extensions.register_reorder_action(:my_feature, label: "Do it",
#       path: ->(items_with_quantities) { ... }, visible: ->(person) { true }, method: :post)
#
#     # Quantities on order: called with a list of items, returns
#     # { item_id => quantity }. Summed when several are registered.
#     Inventory.extensions.register_on_order(->(items) { { ... } })
#
#     # A panel on the item page (rendered with the locals item: and
#     # viewer:), shown when visible.call(item, person) is true.
#     Inventory.extensions.register_item_panel(:my_feature, partial: "my_feature/item_panel",
#       visible: ->(item, person) { true })
#
#     # Extra fields on the item source form (rendered with the locals
#     # item_source: and form:), and the extra params they permit.
#     Inventory.extensions.register_source_fields(:my_feature, partial: "my_feature/source_fields",
#       permit: [ :vendor_id ])
#   end
#
# Registering the same key again replaces the earlier entry.
#
# Notifications:
#
#   stock_movement_recorded.gatherpack  movement:, item:, location:, kind:,
#                                       quantity:, person:, stock_after: (at
#                                       the location), total_after:, went_low:
#
# Published after the movement commits, one per row (a move publishes two).
module Inventory
  # A domain action that isn't allowed, or not by this person. The message
  # is fit to show.
  class Refused < StandardError; end

  # Installing a unit marked Needs repair or Broken without confirm: true.
  # The message is the question to ask.
  class ConfirmNeeded < Refused; end

  ITEM_EVENTS = {
    running_low: "items - running_low",
    out_of_stock: "items - out_of_stock",
    restocked: "items - restocked"
  }.freeze
  COUNT_DIFFERS_EVENT = "stock_movements - count_differs"
  UNIT_EVENTS = {
    needs_repair: "item_units - needs_repair",
    installed: "item_units - installed",
    removed: "item_units - removed"
  }.freeze

  # The manager pages: label, route helper, icon. In the menu where entries
  # can be hidden per person, and linked from the Inventory pages.
  MANAGER_PAGES = [
    [ "Reorder", :inventory_reorder_path, "cart-flatbed" ],
    [ "Items", :inventory_items_path, "box" ],
    [ "Places", :inventory_locations_path, "warehouse" ],
    [ "Changes", :inventory_movements_path, "right-left" ]
  ].freeze

  # The Setup page heading inventory's buttons go under, shared with orders.
  SETUP_SECTION = "Orders and Inventory"

  # The icon of a machine (a place parts get installed on) and its pages.
  MACHINE_ICON = "gears"

  HOOK_TARGETS = %w[items item_sources locations stock_movements item_units item_unit_events].freeze
  HOOK_EVENTS = (ITEM_EVENTS.values + [ COUNT_DIFFERS_EVENT ] + UNIT_EVENTS.values).freeze

  class Extensions
    ReorderAction = Struct.new(:key, :label, :path, :visible, :method, keyword_init: true) do
      def visible?(person)
        visible.nil? || visible.call(person)
      end

      # Changes nothing, so it may run from a GET.
      def get?
        method == :get
      end
    end
    ItemPanel = Struct.new(:key, :partial, :visible, keyword_init: true) do
      def visible?(item, person)
        visible.nil? || visible.call(item, person)
      end
    end
    SourceFields = Struct.new(:key, :partial, :permit, keyword_init: true)

    def initialize
      reset!
    end

    def register_reorder_action(key, label:, path:, visible: nil, method: :post)
      method = method.to_s.downcase.to_sym
      raise ArgumentError, "method must be :get or :post" unless %i[get post].include?(method)

      @reorder_actions[key.to_sym] = ReorderAction.new(key: key.to_sym, label: label, path: path, visible: visible,
        method: method)
    end

    def register_on_order(callable)
      @on_order << callable unless @on_order.include?(callable)
    end

    def register_item_panel(key, partial:, visible: nil)
      @item_panels[key.to_sym] = ItemPanel.new(key: key.to_sym, partial: partial, visible: visible)
    end

    def register_source_fields(key, partial:, permit: [])
      @source_fields[key.to_sym] = SourceFields.new(key: key.to_sym, partial: partial, permit: Array(permit))
    end

    def reorder_actions(person = nil)
      @reorder_actions.values.select { |action| person.nil? || action.visible?(person) }
    end

    def item_panels(item = nil, person = nil)
      @item_panels.values.select { |panel| item.nil? || panel.visible?(item, person) }
    end

    def source_fields
      @source_fields.values
    end

    # The extra params every registered source field permits.
    def source_permitted_params
      source_fields.flat_map(&:permit)
    end

    # { item_id => quantity } on order, summed over every registered
    # callable. Empty when nothing is registered.
    def on_order(items)
      items = Array(items)
      return {} if items.empty? || @on_order.empty?

      @on_order.each_with_object(Hash.new(0)) do |callable, totals|
        (callable.call(items) || {}).each { |item_id, quantity| totals[item_id] += quantity.to_i }
      end
    end

    def on_order?
      @on_order.any?
    end

    def reset!
      @reorder_actions = {}
      @on_order = []
      @item_panels = {}
      @source_fields = {}
    end
  end

  def self.extensions
    @extensions ||= Extensions.new
  end

  def self.enabled?
    GatherPack::Features.enabled?(:inventory)
  end

  # The manager pages this person may open, as [label, route helper, icon]:
  # all of them for inventory managers, team managers and admins, none for
  # anyone else.
  def self.manager_pages(person)
    Inventory::Access.for(person).manager? ? MANAGER_PAGES : []
  end

  # Fires a hook event with a record, while the feature is on.
  def self.run_hooks(event, record)
    return unless enabled?

    Hook.where(event: event).each { |hook| hook.run(record) }
  end

  def self.movement_recorded(movement, stock_after:, total_after:, went_low:)
    return unless enabled?

    ActiveSupport::Notifications.instrument("stock_movement_recorded.gatherpack",
      movement: movement, item: movement.item, location: movement.location, kind: movement.kind,
      quantity: movement.quantity, person: movement.person, stock_after: stock_after,
      total_after: total_after, went_low: went_low)
  end
end
