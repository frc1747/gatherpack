# One thing to buy on a request. Its vendor is a Vendor, an "Other store"
# name, or neither ("Not sure", left to the buyer). Once its request is
# approved, a line moves through its own statuses (spec §3.2); before that
# it's pending.
#
# The actions below take the request's row lock and write the timeline.
class OrderLine < ApplicationRecord
  has_neat_id :ordl
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :order_request, inverse_of: :order_lines
  belongs_to :vendor, optional: true
  belongs_to :purchase, optional: true
  belongs_to :funding_source, optional: true
  belongs_to :item, polymorphic: true, optional: true
  has_many :order_deliveries, -> { order(:received_on, :created_at) }, dependent: :restrict_with_error
  has_one_attached :photo

  enum :status, {
    pending: 0, approved: 1, ordered: 2, backordered: 3, partly_received: 4,
    received: 5, problem: 6, cancelled: 7, needs_reapproval: 8
  }

  monetize :estimated_unit_price_cents, allow_nil: true
  monetize :actual_unit_price_cents, allow_nil: true

  # Fields the requester (and approvers, before approval) edit.
  EDITABLE_FIELDS = %w[
    description manufacturer manufacturer_part_number vendor_id other_vendor_name other_vendor_reason
    vendor_part_number url quantity unit units_per estimated_unit_price_cents funding_source_id note
  ].freeze
  OPEN_TO_RECEIVE = %w[ordered backordered partly_received].freeze
  CONDITIONS_OK = %w[good].freeze

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :units_per, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :estimated_unit_price_cents, :actual_unit_price_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :link_or_description
  validate :other_vendor_reason_given
  validate :funding_source_usable

  before_validation :tidy_vendor
  after_save :remember_status_change
  after_commit :announce_status_changes
  after_rollback :forget_status_changes

  def self.ransackable_attributes(auth_object = nil)
    %w[description status vendor_id purchase_id expected_on created_at]
  end

  def identifier_icon
    "box"
  end

  def identifier_name
    display_name
  end

  def display_name
    description.presence || url_host || url.presence || "Item"
  end

  def url_host
    Vendor.host_of(url) if url.present?
  end

  def vendor_choice
    if vendor_id then :vendor
    elsif other_vendor_name.present? then :other
    else :not_sure
    end
  end

  def not_sure?
    vendor_choice == :not_sure
  end

  def vendor_name
    vendor&.name || other_vendor_name.presence
  end

  def unit_price_cents
    actual_unit_price_cents || estimated_unit_price_cents
  end

  def cost_cents
    quantity.to_i * unit_price_cents.to_i
  end

  def cost
    Money.new(cost_cents)
  end

  # The line's own source, or its request's.
  def effective_funding_source_id
    funding_source_id || order_request&.funding_source_id
  end

  def effective_funding_source
    funding_source || order_request&.funding_source
  end

  # Still waiting for some of its quantity. A problem item is too while
  # some of it is yet to come (the rest of a box that arrived damaged).
  def open_to_receive?
    status.in?(OPEN_TO_RECEIVE) || (problem? && to_come_quantity.positive?)
  end

  # Quantity that arrived damaged or wrong and the buyer hasn't settled yet:
  # the most a replacement can be for.
  def problem_quantity
    unsettled_deliveries.reject(&:good?).sum(&:quantity)
  end

  # Quantity still on its way: what was ordered, less what arrived good and
  # what arrived damaged or wrong and is waiting on the buyer. (A settled
  # problem has already come off the item's quantity.)
  def to_come_quantity
    [ quantity - received_quantity - problem_quantity, 0 ].max
  end

  # Quantity that arrived in good condition.
  def received_quantity
    order_deliveries.select { |delivery| delivery.condition.in?(CONDITIONS_OK) }.sum(&:quantity)
  end

  def outstanding_quantity
    [ quantity - received_quantity, 0 ].max
  end

  # Whether this save raised the line's cost.
  def cost_rose?
    @cost_before.present? && cost_cents > @cost_before
  end

  # The fields changed in memory, as name => [before, after].
  def changes_to_record
    changes.slice(*EDITABLE_FIELDS, "actual_unit_price_cents", "expected_on")
  end

  # Attributes for the same line on a new request ("Order again").
  def reorder_attributes
    attributes.slice(*EDITABLE_FIELDS, "item_type", "item_id")
      .merge("estimated_unit_price_cents" => unit_price_cents)
      .except("funding_source_id")
  end

  # -- Buyer actions --------------------------------------------------------

  def backorder!(by:, expected_on: nil, comment: nil)
    within_lock do
      raise Orders::Refused, "Only an ordered item can be marked delayed." unless ordered? || partly_received?

      from = status
      update!(status: :backordered, expected_on: expected_on)
      order_request.log!(:backordered, by: by, line: self, comment: comment,
        changes: { "status" => [ from, "backordered" ], "expected_on" => [ nil, expected_on&.iso8601 ] })
    end
  end

  # Changes the quantity after approval. Lowering it never needs
  # approval; raising it past the tolerance does.
  def change_quantity!(quantity, by:, comment: nil)
    within_lock do
      unless approved? || ordered? || backordered? || needs_reapproval?
        raise Orders::Refused, "This item's quantity can't be changed now."
      end

      remember_cost
      from = self.quantity
      update!(quantity: quantity)
      order_request.log!(:edited, by: by, line: self, changes: { "quantity" => [ from, self.quantity ] }, comment: comment)
      order_request.order_lines.reset
      order_request.check_price_tolerance([ self ], by: by) if self.quantity > from
    end
  end

  # Buys part now and the rest later: this line keeps quantity_now and a
  # new line waits for a buyer with the rest. Returns the new line.
  def split!(quantity_now, by:)
    within_lock do
      raise Orders::Refused, "Only an item waiting for a buyer can be split." unless approved? && purchase_id.nil?
      quantity_now = quantity_now.to_i
      raise Orders::Refused, "Split off fewer than #{quantity}." unless quantity_now.positive? && quantity_now < quantity

      rest = quantity - quantity_now
      update!(quantity: quantity_now)
      copy = order_request.order_lines.create!(
        attributes.except("id", "neat_id", "created_at", "updated_at", "purchase_id", "position")
          .merge("quantity" => rest, "status" => "approved",
            "position" => (order_request.order_lines.maximum(:position) || 0) + 1)
      )
      order_request.log!(:edited, by: by, line: self, comment: "Split: #{quantity_now} now, #{rest} later",
        changes: { "quantity" => [ quantity_now + rest, quantity_now ] })
      copy
    end
  end

  # Won't be bought; a reason is required.
  def cancel!(by:, reason:)
    raise Orders::Refused, "Give a reason for cancelling." if reason.blank?

    within_lock do
      raise Orders::Refused, "This item can't be cancelled now." if cancelled? || received?
      unless order_request.status.in?(%w[approved ordering received])
        raise Orders::Refused, "Remove items before approval from the request instead."
      end

      from = status
      update!(status: :cancelled)
      order_request.log!(:cancelled, by: by, line: self, comment: reason, changes: { "status" => [ from, "cancelled" ] })
      order_request.refresh_status_from_lines
    end
  end

  # -- Receiving ----------------------------------------------------------

  # Records a delivery. Good items count towards the quantity; damaged or
  # wrong ones make the line a problem for its buyer. Receiving
  # extensions run with the saved delivery and params.
  def record_delivery!(by:, quantity:, received_on: Date.current, condition: :good, note: nil, photo: nil, params: {})
    within_lock do
      raise Orders::Refused, "This item isn't waiting to be received." unless open_to_receive? || problem?

      delivery = order_deliveries.create!(quantity: quantity, received_by: by, received_on: received_on || Date.current,
        condition: condition, note: note, photo: photo)
      from = status
      status_now =
        if !delivery.good? then :problem
        elsif received_quantity >= self.quantity then :received
        elsif problem? then :problem
        else :partly_received
        end
      update!(status: status_now)
      order_request.log!(status_now == :problem ? :problem : :received, by: by, line: self, comment: note,
        changes: { "status" => [ from, status_now.to_s ], "quantity" => delivery.quantity, "condition" => delivery.condition })
      order_request.refresh_status_from_lines
      Orders.after_receive(delivery, params)
      delivery
    end
  end

  # Marks the line received with no delivery record (it went straight to
  # whoever needed it).
  def mark_received!(by:, note:)
    raise Orders::Refused, "Say where it went." if note.blank?

    within_lock do
      raise Orders::Refused, "This item isn't waiting to be received." unless open_to_receive? || problem?

      from = status
      update!(status: :received)
      order_request.log!(:received, by: by, line: self, comment: note, changes: { "status" => [ from, "received" ] })
      order_request.refresh_status_from_lines
    end
  end

  # The buyer settles a problem, the pieces that arrived damaged or wrong.
  # :reorder adds a like-for-like line, ready to buy with no new approval,
  # for quantity of them (default: all); :cancel gives up on them. Pieces
  # still on their way stay on this item, which goes back to ordered or
  # partly here; with none coming it's finished: received if some arrived
  # good, otherwise cancelled. Returns the new line for :reorder.
  def resolve_problem!(resolution, by:, comment: nil, quantity: nil)
    resolution = resolution.to_s
    raise Orders::Refused, "Choose reorder or cancel." unless %w[reorder cancel].include?(resolution)
    raise Orders::Refused, "Give a reason for cancelling." if resolution == "cancel" && comment.blank?

    within_lock do
      raise Orders::Refused, "This item has no problem to resolve." unless problem?

      damaged = problem_quantity
      missing = quantity.present? ? quantity.to_i : damaged
      if resolution == "reorder" && !missing.between?(1, damaged)
        raise Orders::Refused, "Order between 1 and #{damaged} to replace."
      end

      carries_on = to_come_quantity.positive?
      finished =
        if carries_on then received_quantity.positive? ? :partly_received : :ordered
        elsif received_quantity.positive? then :received
        else :cancelled
        end
      replacement = nil
      if resolution == "reorder"
        replacement = order_request.order_lines.create!(
          reorder_attributes.merge("quantity" => missing, "status" => "approved", "vendor_id" => vendor_id,
            "funding_source_id" => funding_source_id, "position" => (order_request.order_lines.maximum(:position) || 0) + 1)
        )
      end
      changes = { "status" => [ "problem", finished.to_s ], "resolution" => resolution }
      changes["reordered"] = missing if replacement
      if carries_on
        from = self.quantity
        update!(status: finished, quantity: from - damaged)
        changes["quantity"] = [ from, self.quantity ]
        order_request.log!(:edited, by: by, line: self, comment: comment, changes: changes)
      else
        update!(status: finished)
        order_request.log!(finished == :received ? :received : :cancelled, by: by, line: self, comment: comment, changes: changes)
      end
      order_request.refresh_status_from_lines
      replacement
    end
  end

  # -- Funding -----------------------------------------------------------

  # Moves a bought line to another source after the fact, with a reason.
  def reallocate_funding!(source, by:, reason:)
    raise Orders::Refused, "Give a reason for moving it." if reason.blank?

    within_lock do
      raise Orders::Refused, "Only a bought item can be moved to another source." if purchase_id.nil?

      before = effective_funding_source
      update!(funding_source: source)
      order_request.log!(:edited, by: by, line: self, comment: reason,
        changes: { "funding_source" => [ before&.name, source&.name ] })
    end
  end

  def remember_cost
    @cost_before = cost_cents
  end

  private

  # Deliveries since the buyer last settled a problem on this item.
  def unsettled_deliveries
    settled_at = OrderRequestEvent.where(order_line_id: id).where("field_changes ->> 'resolution' IS NOT NULL").maximum(:created_at)
    order_deliveries.select { |delivery| settled_at.nil? || delivery.created_at > settled_at }
  end

  # Runs the block holding the request's row lock, with this line read
  # again under it.
  def within_lock(&block)
    order_request.locked do
      reload
      block.call
    end
  end

  def tidy_vendor
    self.other_vendor_name = nil if vendor_id.present?
    self.other_vendor_name = other_vendor_name.strip.presence if other_vendor_name
  end

  def link_or_description
    errors.add(:base, "Give a link or say what it is") if url.blank? && description.blank?
  end

  def other_vendor_reason_given
    return unless vendor_choice == :other && Orders::Config.require_other_vendor_reason?

    errors.add(:other_vendor_reason, "is needed for another store") if other_vendor_reason.blank?
  end

  def funding_source_usable
    return if funding_source.nil? || !will_save_change_to_funding_source_id? || order_request.nil?

    errors.add(:funding_source, "can't be used by #{order_request.team&.name}") unless funding_source.usable_by?(order_request.team)
  end

  # Keeps the status the line had when the transaction started, and whether
  # it joined a purchase, for the hooks at commit.
  def remember_status_change
    @status_at_start = saved_change_to_status.first if saved_change_to_status? && !defined?(@status_at_start)
    @joined_purchase = true if saved_change_to_purchase_id? && purchase_id_before_last_save.nil? && purchase_id.present?
  end

  # Fires once per transaction: "ordered" when the line joined a purchase
  # (even if a price past the tolerance then sent it for re-approval, and
  # not again when that's approved), and the other events for the status
  # the line ends up in.
  def announce_status_changes
    from = @status_at_start if defined?(@status_at_start)
    joined = @joined_purchase
    forget_status_changes

    Orders.run_hooks(Orders::LINE_STATUS_EVENTS["ordered"], self) if joined
    return if from.nil? || from == status || status == "ordered"

    event = Orders::LINE_STATUS_EVENTS[status]
    Orders.run_hooks(event, self) if event
  end

  def forget_status_changes
    remove_instance_variable(:@status_at_start) if defined?(@status_at_start)
    @joined_purchase = nil
  end
end
