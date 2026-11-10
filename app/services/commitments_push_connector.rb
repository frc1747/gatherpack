# Prepended to CommitmentsController from config/initializers/phone_notifications_connectors.rb.
# Phones get a notification for each person the organizer's message was emailed
# to. The emails are queued first, and a failure here can't stop them.
module CommitmentsPushConnector
  def message
    super
    send_push_notifications
  end

  private
    # Mirrors who #message emailed: nothing went out without a subject and body.
    def send_push_notifications
      return unless GatherPack::PushChannel.available?
      return if params[:subject].to_s.strip.blank? || params[:body].to_s.strip.blank?

      title = "Reminder: #{@commitment.title}"
      emailed_people.each do |person|
        GatherPack::PushChannel.deliver(person, topic: :commitments, title: title, path: commitment_push_path(person))
      end
    rescue StandardError => e
      Rails.logger.error("Commitment phone notifications failed: #{e.class}: #{e.message}")
    end

    def emailed_people
      open = @commitment.progress.values.uniq.reject(&:met?).flat_map(&:members)
      open.uniq.select { |person| person.user&.email.present? }
    end

    # The commitment itself when that person can open it, else their own list.
    def commitment_push_path(person)
      urls = Rails.application.routes.url_helpers
      CommitmentPolicy.new(person.user, @commitment).show? ? urls.commitment_path(@commitment) : urls.person_commitments_path(person)
    end
end
