class SentEmailsController < InternalController
  before_action :require_email_log

  # GET /sent_emails
  def index
    authorize SentEmail
    @q = policy_scope(SentEmail).ransack(params[:q])
    @sent_emails = @q.result.includes(:person, :about).newest_first.page(params[:page])
    @people = Person.where(id: SentEmail.where.not(person_id: nil).select(:person_id)).order(:display_name)
    @about_types = SentEmail.where.not(about_type: nil).distinct.pluck(:about_type).sort
  end

  private
    def require_email_log
      redirect_to root_path, notice: "The sent email log is turned off." unless EmailLog.enabled?
    end
end
