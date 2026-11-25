# A CSV uploaded to a file source (Gateway::FileSource): the file as
# uploaded, the records Accounting::Files::Reader read from it and its row
# errors, shown as a preview until an admin applies it. Applying replaces the
# source's records with the file's. No audit log: like the records, the
# file is the history.
class AccountingUpload < ApplicationRecord
  has_neat_id :acup

  STATUSES = %w[ previewed applying applied ].freeze

  belongs_to :gateway
  belongs_to :created_by, class_name: "Person", optional: true
  belongs_to :applied_by, class_name: "Person", optional: true

  validates :content, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :applied, -> { where(status: "applied") }

  # Reads content into parsed_records, row_errors and row_count.
  def read_content
    result = Accounting::Files::Reader.new(content).read
    self.parsed_records = result.records
    self.row_errors = result.errors
    self.row_count = result.row_count
    self
  end

  def problems?
    row_errors.any?
  end

  def appliable?
    status == "previewed" && !problems?
  end

  def identifier_name
    filename.presence || "Upload"
  end
end
