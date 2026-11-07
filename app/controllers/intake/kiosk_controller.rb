# /join/:slug/kiosk: sign-ups in the room, on a signed-in device. A manager
# is present, so the person, login (with a random password, not yet
# verified) and applications are made at once, and the person finishes at
# home from the invitation email. The screen shows only what was typed:
# never existing records, matches, or anything private. Matches are for
# managers, on "Waiting to finish".
#
# Open to admins, and to managers of the registration's team (or a team
# above it) who are direct members of the kiosk accounts team
# (intake_kiosk_users_team, else the time kiosk's; when neither is set, any
# such manager).
class Intake::KioskController < InternalController
  include Intake::PublicPages

  layout "intake_kiosk"

  before_action :set_registration
  before_action :require_kiosk_account

  # GET /join/:slug/kiosk
  def show
    @form = {}
    @answers = {}
  end

  # POST /join/:slug/kiosk
  def create
    @form = kiosk_params.to_h
    @answers = answer_params
    if intake_over_limit?("kiosk", current_user.id, to: Intake.setting(:intake_rate_kiosk_per_minute, 30), within: 1.minute)
      flash.now[:alert] = Intake::PublicPages::TRY_AGAIN
      return render :show, status: :too_many_requests
    end

    @errors = form_errors
    return render(:show, status: :unprocessable_content) if @errors.any?

    @first_name = @form["first_name"].strip
    Intake::Entry.transaction { sign_up }
    render :thanks
  end

  private

  def set_registration
    @registration = Intake::Registration.find_by(slug: params[:slug].to_s)
    render "intake/join/closed", layout: "intake_public", status: :not_found unless @registration&.kiosk_open?
  end

  def require_kiosk_account
    return if current_user.admin
    person = current_user.person
    manages = person&.all_managed_teams&.exists?(id: @registration.team_id)
    # Both settings hold a team's id. One that names no team (deleted, or
    # an old value) lets nobody but admins in.
    team_id = Settings[:intake_kiosk_users_team].to_s.strip.presence || Settings[:time_kiosk_users_team].to_s.strip.presence
    kiosk_team = team_id && (Team.find_by(id: team_id) || :missing)
    on_team = kiosk_team.nil? || (kiosk_team != :missing && person.teams.exists?(id: kiosk_team.id))
    return if manages && on_team

    redirect_to root_path, alert: "The registration kiosk is for kiosk accounts only."
  end

  def kiosk_params
    params.fetch(:kiosk, {}).permit(:first_name, :last_name, :birth_year, :email, :email_confirmation,
      :guardian_first_name, :guardian_last_name, :guardian_email, team_ids: [])
  end

  # Answers to the registration's first-step questions, by field key.
  def answer_params
    keys = @registration.kiosk_fields.map(&:key)
    values = params.dig(:person, :person_field_values)
    return {} unless values.respond_to?(:permit)
    # A key may come as one value or, for a multi-select, a list.
    values.permit(*keys, **keys.index_with { [] }).to_h
  end

  def normalized_answers
    @normalized_answers ||= @registration.kiosk_fields.each_with_object({}) do |field, answers|
      value, error = field.normalize(@answers[field.key], current: nil)
      answers[field] = [ value, error ]
    end
  end

  def team_ids
    chosen = Array(@form["team_ids"]).map(&:to_s) & @registration.apply_team_ids
    chosen.presence || (@registration.apply_team_ids.one? ? @registration.apply_team_ids : [])
  end

  def needs_guardian?
    Intake.needs_guardian?(birth_year: @form["birth_year"])
  end

  def form_errors
    errors = []
    errors << "Choose at least one team." if team_ids.empty?
    errors << "Enter a first and last name." if @form["first_name"].blank? || @form["last_name"].blank?
    year = @form["birth_year"].to_s
    errors << "Enter the year you were born." unless year.match?(/\A\d{4}\z/) && year.to_i.between?(Date.current.year - 110, Date.current.year)
    email = Intake.normalize_email(@form["email"])
    if !email.match?(URI::MailTo::EMAIL_REGEXP)
      errors << "Enter a valid email."
    elsif email != Intake.normalize_email(@form["email_confirmation"])
      errors << "The two emails don't match."
    end
    if needs_guardian? && @registration.guardian_relationship_type
      guardian_email = Intake.normalize_email(@form["guardian_email"])
      if @form["guardian_first_name"].blank? || @form["guardian_last_name"].blank? || !guardian_email.match?(URI::MailTo::EMAIL_REGEXP)
        errors << "Enter a guardian's name and email."
      elsif guardian_email == email
        errors << "The guardian's email must be their own."
      end
    end
    normalized_answers.each do |field, (value, error)|
      if error
        errors << "#{field.name} #{error}."
      elsif field.required? && value.blank? && value != false
        errors << "#{field.name} can't be blank."
      end
    end
    errors
  end

  # The same work for an email with a login and a new one; the screen says
  # the same either way.
  # Answers are written only for someone new to the site, as they typed them
  # and where the field lets a person set their own. Someone already on
  # file isn't changed from a shared screen; the answers stay on the entry.
  def save_answers(person)
    access = PersonFieldAccess.new(person, person)
    normalized_answers.each do |field, (value, _)|
      person.set_field_value(field, value) if !value.nil? && access.writable?(field)
    end
  end

  def sign_up
    email = Intake.normalize_email(@form["email"])
    user = Intake.user_for_email(email)
    new_login = user.nil?
    user ||= User.create!(email: email, password: Devise.friendly_token[0, 24],
      person: Person.new(first_name: @form["first_name"].strip, last_name: @form["last_name"].strip))
    person = user.person || Person.create!(user: user, first_name: @form["first_name"].strip, last_name: @form["last_name"].strip)

    entry = @registration.entries.create!(source: :kiosk, email: email, first_name: @form["first_name"].strip, last_name: @form["last_name"].strip,
      person: person, created_ip_prefix: Intake.ip_prefix(request.remote_ip),
      facts: { "team_ids" => team_ids, "birth_year" => @form["birth_year"], "needs_guardian" => needs_guardian?, "new_login" => new_login,
        "answers" => normalized_answers.to_h { |field, (value, _)| [ field.key, value ] }.compact })
    save_answers(person) if new_login
    enrollment = Intake::Enrollment.new(entry)
    enrollment.applicant_member!(person)
    enrollment.apply(person)

    if needs_guardian? && @registration.guardian_relationship_type && !person.guardians.exists?
      row = enrollment.name_guardian(ward: person, first_name: @form["guardian_first_name"], last_name: @form["guardian_last_name"],
        email: @form["guardian_email"])
      Intake::GuardianEmailJob.perform_later(row.id)
    end
    Intake::EntryEmailJob.perform_later(entry.id)
  end
end
