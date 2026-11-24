# One email GatherPack handed to a sending gateway, and what the sending
# service reported about it afterwards (delivered, bounced, complained, link
# clicked, opened). Written by SendEmailJob and updated from the gateway's
# webhooks through Gateway#record_delivery_event, only while the email log
# feature is on. No body, IP address or browser is kept.
class SentEmail < ApplicationRecord
  has_neat_id :sem

  # Tied to code: the job and the webhook mapping set them. Their labels are
  # settings (EmailLog.status_label).
  STATUSES = %w[sending sent delivered bounced complained failed].freeze
  PROBLEM_STATUSES = %w[bounced complained failed].freeze

  # What a gateway's webhook can tell us about a message.
  EVENT_KINDS = %i[delivered bounced complained clicked opened].freeze

  belongs_to :gateway, optional: true
  belongs_to :person, optional: true
  belongs_to :about, polymorphic: true, optional: true

  validates :address, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :newest_first, -> { order(created_at: :desc) }

  def self.ransackable_attributes(auth_object = nil)
    %w[address subject status person_id about_type created_at sent_at]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end

  def status_label
    EmailLog.status_label(status)
  end

  def problem?
    PROBLEM_STATUSES.include?(status)
  end

  def sent!(provider_message_id)
    update!(status: "sent", sent_at: Time.current, provider_message_id: provider_message_id.presence)
  end

  def failed!(error)
    update!(status: "failed", problem_at: Time.current, problem_detail: error&.message.to_s.truncate(500))
  end

  # Applies one webhook event. Later events never undo a problem: a message
  # reported delivered after it bounced stays bounced.
  def record_event(kind, at:, url: nil, detail: nil)
    at ||= Time.current

    case kind.to_sym
    when :delivered
      self.delivered_at ||= at
      self.status = "delivered" unless problem?
    when :bounced, :complained
      self.status = kind.to_s
      self.problem_at = at
      self.problem_detail = detail.to_s.truncate(500) if detail.present?
    when :clicked
      record_click(at, url)
    when :opened
      self.opened_at ||= at
    else
      return false
    end

    save!
  end

  # When a person first clicked a link, or nil. Mail scanners follow links as
  # the message arrives, so a click within email_log_scanner_seconds of
  # delivery is counted but isn't shown as the person's.
  def link_clicked_at
    first_clicked_at unless scanner_click?(first_clicked_at)
  end

  private
    def record_click(at, url)
      self.click_count += 1
      return unless first_clicked_at.nil? || better_first_click?(at)

      self.first_clicked_at = at
      self.first_clicked_url = url.present? ? url.to_s.truncate(2000) : nil
    end

    # A person's click beats a scanner's; otherwise the earlier one wins
    # (webhooks can arrive out of order).
    def better_first_click?(at)
      kept_by_scanner = scanner_click?(first_clicked_at)
      return kept_by_scanner if kept_by_scanner != scanner_click?(at)

      at < first_clicked_at
    end

    def scanner_click?(at)
      return false if at.nil? || delivered_at.nil?

      at - delivered_at < EmailLog.scanner_seconds
    end
end
