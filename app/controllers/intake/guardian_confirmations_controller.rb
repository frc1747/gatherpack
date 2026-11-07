# The link in "Confirm you are their guardian": /join/guardian?token=...
# Confirming verifies the guardian's email, finds their login by that email
# or makes one, and links them as the young person's guardian. A young
# person can't make the tie; only the guardian's confirmation does.
class Intake::GuardianConfirmationsController < ApplicationController
  include Intake::PublicPages

  skip_before_action :check_for_user
  before_action :limit_requests
  before_action :set_row

  # GET /join/guardian?token=...
  def show
    @user = existing_login || new_login
  end

  # POST /join/guardian
  def create
    if (user = existing_login)
      return render_refused if as_entry(@row.entry) { confirm(user.person) } == :refused
      session[:user_return_to] = intake_me_path(@row.entry.registration.slug)
      return render :sign_in
    end

    @user = new_login
    @user.assign_attributes(password: params[:password], password_confirmation: params[:password_confirmation], intake_login_verified_at: Time.current)
    saved = as_entry(@row.entry) do
      User.transaction do
        @user.save && (@user.person.save || raise(ActiveRecord::Rollback)) && confirm(@user.person)
      end
    end
    return render(:show, status: :unprocessable_content) unless saved
    return render_refused if saved == :refused

    sign_in(@user)
    redirect_to intake_me_path(@row.entry.registration.slug), notice: "Thanks. You're linked as #{@row.ward.first_name}'s guardian."
  end

  private

  def limit_requests
    return unless verification_over_limit?
    flash.now[:alert] = Intake::PublicPages::TRY_AGAIN
    render "intake/verifications/expired", status: :too_many_requests
  end

  def set_row
    @token = params[:token].to_s
    @row = Intake::HouseholdMember.find_guardian_by_token(@token)
    return render("intake/verifications/expired", status: :not_found) unless @row&.ward
    # The registration stopped linking guardians while this waited.
    render_refused unless @row.entry.registration.guardian_relationship_type
  end

  def existing_login
    Intake.user_for_email(@row.facts["email"])
  end

  def new_login
    User.new(email: @row.facts["email"], person: Person.new(first_name: @row.facts["first_name"], last_name: @row.facts["last_name"]))
  end

  # Returns true, or :refused when the link's young person is the one
  # opening it (a young person can't be their own guardian).
  def confirm(guardian)
    Intake::Enrollment.new(@row.entry).confirm_guardian(@row, guardian)
    # A young person's own invitation waits for their guardian (kiosk).
    entry = @row.entry
    Intake::EntryEmailJob.perform_later(entry.id) if entry.source_kiosk? && entry.verified_at.nil? && entry.person == @row.ward
    true
  rescue Intake::Enrollment::Refused
    :refused
  end

  def render_refused
    render "intake/verifications/expired", status: :unprocessable_content
  end
end
