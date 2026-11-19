# Where an item can be bought: a free-text vendor name, the vendor's part
# number and a link. At most one source per item is preferred.
class ItemSource < ApplicationRecord
  has_neat_id :isrc
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  belongs_to :item, inverse_of: :item_sources

  validates :vendor_name, presence: true

  after_save :unprefer_others, if: -> { preferred? && saved_change_to_preferred? }

  scope :ordered, -> { order(preferred: :desc, position: :asc, created_at: :asc) }

  def self.ransackable_attributes(auth_object = nil)
    %w[vendor_name vendor_part_number preferred]
  end

  def identifier_name
    vendor_name
  end

  def identifier_icon
    "store"
  end

  private

  def unprefer_others
    ItemSource.where(item_id: item_id, preferred: true).where.not(id: id).find_each { |source| source.update!(preferred: false) }
  end
end
