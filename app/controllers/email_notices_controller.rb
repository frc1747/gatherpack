# Each person's choice of how they hear about each summary section
# (GatherPack::Digests): an email each time, the daily digest, the Weekly
# Infodump, off, or the site's choice.
class EmailNoticesController < InternalController
  SITE = "site".freeze

  before_action :require_sections

  # GET /email_notices: where the Notifications page takes other features'
  # cards, the choices live there and this address leads to it.
  def show
    authorize :email_notice
    redirect_to notifications_path if GatherPack::Digests.on_notifications_page?
  end

  # PATCH /email_notices
  def update
    authorize :email_notice
    person = current_user.person
    chosen = params.fetch(:email_notices, {})
    choices = GatherPack::Digests.personal_entries
      .to_h { |entry| [ entry.key.to_s, chosen[entry.key.to_s].to_s ] }
      .compact_blank

    unless choices.values.all? { |choice| choice == SITE || NoticePreference::DELIVERIES.include?(choice) }
      redirect_to back_path, alert: "Choose one of the options"
      return
    end

    NoticePreference.transaction do
      choices.each do |key, choice|
        if choice == SITE
          NoticePreference.where(person: person, key: key).delete_all
        else
          NoticePreference.find_or_initialize_by(person: person, key: key).update!(delivery: choice)
        end
      end
    end

    redirect_to back_path, notice: "Saved"
  end

  private

  def back_path
    GatherPack::Digests.on_notifications_page? ? notifications_path(anchor: "email-notices") : email_notices_path
  end

  def require_sections
    redirect_to root_path if GatherPack::Digests.personal_entries.empty?
  end
end
