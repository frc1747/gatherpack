# The link in "Finish joining": /join/verify?token=... (a query parameter,
# so the log's filtered path hides it). Opening it shows a page; only
# submitting that page uses the link, so a mail scanner that follows links
# can't. For a new email it creates the person and login and asks for a
# password. For an email that already has a login it attaches the entry to
# that person and says to sign in; it never signs anyone in.
class Intake::VerificationsController < ApplicationController
  include Intake::PublicPages

  skip_before_action :check_for_user
  before_action :limit_requests
  before_action :set_entry

  # GET /join/verify?token=...
  def show
    @existing_login = existing_login.present?
    @user = new_login
  end

  # POST /join/verify
  def create
    if (user = existing_login)
      as_entry(@entry) { attach(user.person) }
      session[:user_return_to] = intake_me_path(@entry.registration.slug)
      return render :sign_in
    end

    @user = new_login
    @user.assign_attributes(password: params[:password], password_confirmation: params[:password_confirmation], intake_login_verified_at: Time.current)
    saved = as_entry(@entry) do
      User.transaction do
        @user.save && (@user.person.save || raise(ActiveRecord::Rollback)) && attach(@user.person)
      end
    end
    return render(:show, status: :unprocessable_content) unless saved

    sign_in(@user)
    redirect_to intake_me_path(@entry.registration.slug), notice: "You're signed in. Here's what's next."
  end

  private

  def limit_requests
    return unless verification_over_limit?
    flash.now[:alert] = Intake::PublicPages::TRY_AGAIN
    render :expired, status: :too_many_requests
  end

  def set_entry
    @token = params[:token].to_s
    @entry = Intake::Entry.find_by_token(@token)
    render :expired, status: :not_found unless @entry
  end

  # A kiosk entry made its person and login at once; the link sets the
  # password. Self-service entries have neither until now.
  def new_login
    if @entry.source_kiosk? && @entry.person&.user && @entry.facts["new_login"]
      @entry.person.user
    else
      User.new(email: @entry.email, person: Person.new(first_name: @entry.first_name, last_name: @entry.last_name))
    end
  end

  def existing_login
    return if @entry.source_kiosk? && @entry.facts["new_login"]
    Intake.user_for_email(@entry.email)
  end

  def attach(person)
    enrollment = Intake::Enrollment.new(@entry)
    @entry.verify!(person)
    enrollment.applicant_member!(person)
    enrollment.apply(person)
    true
  end
end
