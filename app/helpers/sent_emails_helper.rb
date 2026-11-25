module SentEmailsHelper
  # The kind of record an email was about, in words ("Order request").
  def sent_email_about_type_label(type)
    type.safe_constantize&.model_name&.human || type.demodulize.titleize
  end

  # A link to the record the email was about, when it still exists and has
  # a page.
  def sent_email_about_link(sent_email)
    about = sent_email.about
    return unless about

    label = about.try(:name).presence || about.try(:title).presence || sent_email_about_type_label(sent_email.about_type)
    link_to label, polymorphic_path(about), data: { turbo_frame: "_top" }
  rescue NoMethodError, ActionController::UrlGenerationError
    sent_email_about_type_label(sent_email.about_type)
  end
end
