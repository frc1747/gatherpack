# The public registration link, /join/:slug. Signed out, it takes a name, an
# email and the teams, and makes only an entry: the person and login come
# when the email is confirmed. Every address gets the same page, words and
# work here; whether it already has a login is decided by the email job.
# Signed in, it applies the person to the teams directly.
class Intake::JoinController < ApplicationController
  include Intake::PublicPages

  skip_before_action :check_for_user
  before_action :set_registration

  # GET /join/:slug
  def show
    @entry = Intake::Entry.new(facts: { "team_ids" => default_team_ids })
    @stamp = Intake::FormGuard.stamp
  end

  # POST /join/:slug
  def create
    return apply_signed_in if current_user

    @entry = @registration.entries.new(id: SecureRandom.uuid, source: :link, first_name: entry_params[:first_name].to_s.strip,
      last_name: entry_params[:last_name].to_s.strip, email: Intake.normalize_email(entry_params[:email]),
      facts: { "team_ids" => chosen_team_ids }, created_ip_prefix: Intake.ip_prefix(request.remote_ip))
    @stamp = Intake::FormGuard.stamp

    if over_start_limits?
      flash.now[:alert] = Intake::PublicPages::TRY_AGAIN
      return render :show, status: :too_many_requests
    end
    # Bots are dropped quietly: they see what a person would.
    return render :thanks if Intake::FormGuard.drop?(params)
    unless Intake::BotCheck.adapter.passed?(params, request)
      # An adapter that can tell a person to retry says so; others drop quietly.
      message = Intake::BotCheck.adapter.try(:failure_message)
      return render :thanks if message.blank?
      @entry.errors.add(:base, message)
      return render(:show, status: :unprocessable_content)
    end
    return render(:show, status: :unprocessable_content) unless @entry.valid?
    return render_busy if @registration.at_entry_cap?

    as_entry(@entry) { @entry.save! }
    Intake::EntryEmailJob.perform_later(@entry.id)
    render :thanks
  end

  private

  def set_registration
    @registration = Intake::Registration.find_by(slug: params[:slug].to_s)
    return if @registration&.self_service_open?
    render :closed, status: :not_found
  end

  def entry_params
    params.fetch(:entry, {}).permit(:first_name, :last_name, :email, team_ids: [])
  end

  def default_team_ids
    ids = @registration.apply_team_ids
    ids.one? ? ids : []
  end

  def chosen_team_ids
    chosen = Array(entry_params[:team_ids]).map(&:to_s) & @registration.apply_team_ids
    chosen.presence || default_team_ids
  end

  # Per network address, per email and per registration. Every limit counts
  # this request, so one can't be used to probe another.
  def over_start_limits?
    [
      intake_over_limit?("start-ip", request.remote_ip, to: Intake.setting(:intake_rate_ip_per_hour, 5), within: 1.hour),
      intake_over_limit?("start-email", Intake.digest(@entry.email), to: Intake.setting(:intake_rate_email_per_hour, 3), within: 1.hour),
      intake_over_limit?("start-registration", @registration.id, to: Intake.setting(:intake_rate_registration_per_hour, 200), within: 1.hour)
    ].any?
  end

  # Managers hear about it once a day at most.
  def render_busy
    store = Intake.rate_limit_store || Rails.cache
    if store.write("intake-busy-notified:#{@registration.id}", true, expires_in: 1.day, unless_exist: true)
      Intake::Notices.registration_busy(@registration)
    end
    render :busy, status: :service_unavailable
  end

  def apply_signed_in
    person = current_user.person
    if chosen_team_ids.empty?
      @entry = Intake::Entry.new(facts: { "team_ids" => [] })
      @entry.errors.add(:base, "Choose at least one team.")
      return render :show, status: :unprocessable_content
    end
    entry = @registration.entries.verified.where(person: person).order(:created_at).last ||
      @registration.entries.create!(source: :link, person: person, verified_at: Time.current, first_name: person.first_name,
        last_name: person.last_name, facts: { "team_ids" => chosen_team_ids })
    enrollment = Intake::Enrollment.new(entry)
    enrollment.applicant_member!(person)
    enrollment.apply(person, chosen_team_ids)
    redirect_to intake_me_path(@registration.slug)
  end
end
