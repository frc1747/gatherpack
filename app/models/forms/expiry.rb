# A form's own optional expiry: its responses stop counting on a date
# (expires_on, for everyone), or a number of months after each one was
# signed (valid_for_months, each person's clock starting when they sign).
# Neither set means responses never expire. An expired response needs
# re-confirmation (Forms::ResponseExpiry), which FormExpiryJob stores.
module Forms::Expiry
  extend ActiveSupport::Concern

  EXPIRY_CHOICES = %w[ never date months ].freeze

  included do
    validates :valid_for_months, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validate :one_expiry

    before_validation :apply_expiry_choice
    # As publishing does: responses past the new expiry stop being complete,
    # and those it no longer covers are complete again.
    after_update_commit :resync_expiry!, if: -> { saved_change_to_expires_on? || saved_change_to_valid_for_months? }
  end

  def expires?
    expires_on.present? || valid_for_months.present?
  end

  # When a response signed (activated) at this time stops counting, or nil.
  # A date takes effect from the start of that day.
  def expiry_for(signed_at)
    if expires_on
      expires_on.in_time_zone
    elsif valid_for_months && signed_at
      signed_at + valid_for_months.months
    end
  end

  # The details choice, "Responses expire": never, on a date, or months
  # after signing. Saving keeps only the column the choice uses.
  def expiry
    @expiry || (expires_on ? "date" : (valid_for_months ? "months" : "never"))
  end

  def expiry=(choice)
    @expiry = choice.presence_in(EXPIRY_CHOICES)
  end

  def resync_expiry!
    form_responses.where.not(active_submission_id: nil).includes(:active_submission).find_each(&:sync_status!)
  end

  private

  def apply_expiry_choice
    self.expires_on = nil unless @expiry.nil? || @expiry == "date"
    self.valid_for_months = nil unless @expiry.nil? || @expiry == "months"
  end

  def one_expiry
    errors.add(:expires_on, "can't be blank") if @expiry == "date" && expires_on.nil?
    errors.add(:valid_for_months, "can't be blank") if @expiry == "months" && valid_for_months.nil?
    errors.add(:base, "Responses can expire on a date or some months after signing, not both") if expires_on && valid_for_months
  end
end
