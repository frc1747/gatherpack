# An order placed with one vendor by a buyer. Holds lines from any number of
# requests. Its total is the lines' actual cost plus shipping and tax; for
# reports and funding, shipping and tax are shared out over its lines in
# proportion to their cost (#extras_shares). Recorded with
# Orders::RecordPurchase.
class Purchase < ApplicationRecord
  has_neat_id :pur
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :vendor, optional: true
  belongs_to :buyer, class_name: "Person"
  belongs_to :payment_method, optional: true
  belongs_to :reimburse_to, class_name: "Person", optional: true
  belongs_to :ledger_entry, optional: true
  has_many :order_lines, dependent: :restrict_with_error
  has_many :order_requests, -> { distinct }, through: :order_lines
  has_many_attached :receipts

  monetize :shipping_cents
  monetize :tax_cents

  validates :shipping_cents, :tax_cents, numericality: { greater_than_or_equal_to: 0 }
  validate :vendor_named

  def self.ransackable_attributes(auth_object = nil)
    %w[vendor_id buyer_id ordered_on expected_on vendor_order_number created_at]
  end

  def identifier_icon
    "truck"
  end

  def identifier_name
    [ vendor_name, vendor_order_number.presence || ordered_on&.to_fs(:short) ].compact.join(" ")
  end

  def vendor_name
    vendor&.name || other_vendor_name
  end

  def live_lines
    order_lines.reject(&:cancelled?)
  end

  # Every line bought on it, including any cancelled since (a problem given
  # up on): they were paid for, and returns aren't tracked.
  def bought_lines
    order_lines.to_a
  end

  def lines_cost_cents
    bought_lines.sum(&:cost_cents)
  end

  def extras_cents
    shipping_cents.to_i + tax_cents.to_i
  end

  def total_cents
    lines_cost_cents + extras_cents
  end

  def total
    Money.new(total_cents)
  end

  # Shipping and tax shared out over the bought lines in proportion to their
  # cost (evenly when they cost nothing), as { line id => cents }. The
  # shares add up to the extras exactly.
  def extras_shares
    lines = bought_lines
    return {} if lines.empty?

    base = lines.sum(&:cost_cents)
    weights = lines.to_h { |line| [ line.id, base.positive? ? line.cost_cents : 1 ] }
    weight_total = weights.values.sum
    shares = weights.transform_values { |weight| extras_cents * weight / weight_total }
    leftover = extras_cents - shares.values.sum
    weights.sort_by { |id, weight| [ -(extras_cents * weight % weight_total), id ] }.first(leftover).each { |id, _| shares[id] += 1 }
    shares
  end

  # Paid with a method that pays the buyer back.
  def reimburse?
    payment_method&.reimburse || false
  end

  # Records the remaining quantity of every open line as received. With
  # only:, just the lines of those requests (the ones the person may
  # receive for).
  def mark_all_received!(by:, only: nil)
    open = order_lines.select { |line| line.open_to_receive? && !line.problem? }
    open = open.select { |line| only.map(&:id).include?(line.order_request_id) } if only
    raise Orders::Refused, "Nothing here is waiting to be received." if open.empty?

    transaction do
      open.map(&:order_request).uniq.sort_by(&:id).each do |order_request|
        order_request.mark_all_received!(by: by, purchase: self)
      end
    end
  end

  private

  def vendor_named
    errors.add(:vendor, "or another store's name is needed") if vendor_id.blank? && other_vendor_name.blank?
  end
end
