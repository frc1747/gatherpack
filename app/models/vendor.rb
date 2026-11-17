# A place things are bought from. Preferred vendors are listed first on the
# request form. A pasted link whose host is in #domains picks the vendor,
# and #part_number_pattern (a regular expression with one capture group)
# pulls the vendor part number out of it.
class Vendor < ApplicationRecord
  has_neat_id :vnd
  include CanBeHooked
  has_paper_trail versions: { class_name: "AuditLog" }

  has_many :order_lines, dependent: :restrict_with_error
  has_many :purchases, dependent: :restrict_with_error

  validates :name, presence: true
  validate :pattern_compiles

  before_validation :normalize_domains

  scope :active, -> { where(active: true) }
  scope :listed, -> { order(preferred: :desc, name: :asc) }

  def self.ransackable_attributes(auth_object = nil)
    %w[name website preferred active]
  end

  def identifier_icon
    "store"
  end

  # The active vendor whose domains include the link's host (or a parent
  # domain of it), or nil.
  def self.for_url(url)
    host = host_of(url)
    return nil if host.nil?

    candidates = host.split(".").each_index.map { |i| host.split(".").drop(i).join(".") }
    active.where("domains && ARRAY[?]::varchar[]", candidates).first
  end

  def self.host_of(url)
    URI.parse(url.to_s.strip).host&.downcase&.delete_prefix("www.")
  rescue URI::InvalidURIError
    nil
  end

  # The vendor part number in the link, or nil when there is no pattern or
  # it doesn't match.
  def part_number_from(url)
    return nil if part_number_pattern.blank?

    Regexp.new(part_number_pattern).match(url.to_s)&.captures&.first.presence
  rescue RegexpError
    nil
  end

  private

  def normalize_domains
    self.domains = Array(domains).flat_map { |domain| domain.to_s.split(/[\s,]+/) }
      .map { |domain| domain.downcase.delete_prefix("www.") }.compact_blank.uniq
  end

  def pattern_compiles
    return if part_number_pattern.blank?

    Regexp.new(part_number_pattern)
  rescue RegexpError => e
    errors.add(:part_number_pattern, "isn't a valid regular expression (#{e.message})")
  end
end
