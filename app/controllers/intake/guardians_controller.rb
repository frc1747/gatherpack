# Managers fix guardian requests on a registration: correct the email of
# one not yet confirmed, send it again, or link a person already on file.
class Intake::GuardiansController < InternalController
  before_action :require_intake_feature
  before_action :set_registration
  before_action :set_row, only: %i[update resend]

  # POST /registrations/:registration_id/guardians (ward_id, guardian: email
  # or person id, row_id: the ward's waiting request on this registration)
  #
  # Only for an applicant who needs a guardian and has none, never with the
  # manager themselves as guardian, and not for the manager's own
  # application or a relative's.
  def create
    ward = applicant_people.find(params[:ward_id])
    row = params[:row_id].presence && registration_rows.unconfirmed_guardians.find(params[:row_id])
    raise ActiveRecord::RecordNotFound if row && row.facts["ward_id"] != ward.id
    guardian = find_guardian(params[:guardian].to_s.strip)
    return back_with(alert: "No one on file has that login email or id.") unless guardian
    return back_with(alert: "#{ward.first_name} doesn't need a guardian linked.") unless Intake.person_needs_guardian?(ward) && !ward.guardians.exists?
    if guardian == current_user.person || Intake.own_or_relatives?(current_user.person, ward)
      return back_with(alert: "Someone else links this guardian: it's you or a relative.")
    end

    Intake::Enrollment.new(entry_for(ward)).link_existing_guardian(ward: ward, guardian: guardian, by: current_user.person, row: row)
    back_with(notice: "Linked #{guardian.display_name} as #{ward.first_name}'s guardian.")
  rescue Intake::Enrollment::Refused => e
    back_with(alert: e.message)
  end

  # PATCH /registrations/:registration_id/guardians/:id (a corrected email)
  def update
    Intake::Enrollment.new(@row.entry).correct_guardian_email(@row, params[:email])
    Intake::GuardianEmailJob.perform_later(@row.id)
    back_with(notice: "Changed, and sent to the new address.")
  rescue Intake::Enrollment::Refused => e
    back_with(alert: e.message)
  end

  # POST /registrations/:registration_id/guardians/:id/resend
  def resend
    return back_with(alert: "A manager confirms this guardian; there's no email to send.") if @row.facts["manager_confirms"]
    store = Intake.rate_limit_store || Rails.cache
    count = store.increment("intake-rate-limit:guardian-resend:#{@row.id}", 1, expires_in: 1.day)
    return back_with(alert: "That request was sent again too often today. Try again tomorrow.") if count && count > Intake.setting(:intake_rate_resend_per_day, 3)

    Intake::GuardianEmailJob.perform_later(@row.id)
    back_with(notice: "Sent again.")
  end

  private

  def require_intake_feature
    redirect_to root_path, notice: "Registration isn't turned on." unless Intake.enabled?
  end

  def set_registration
    @registration = authorize policy_scope(Intake::Registration).find(params[:registration_id]), :update?
  end

  def set_row
    @row = registration_rows.unconfirmed_guardians.find(params[:id])
  end

  def registration_rows
    Intake::HouseholdMember.joins(:entry).where(intake_entries: { registration_id: @registration.id })
  end

  # People with an application from this registration: the only ones a
  # guardian can be linked to from here.
  def applicant_people
    Person.where(id: @registration.membership_applications.select(:person_id))
  end

  def find_guardian(ref)
    return Intake.user_for_email(ref)&.person if ref.include?("@")
    Person.find_by_neat_id(ref) || (ref.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/) && Person.find_by(id: ref)) || nil
  end

  def entry_for(ward)
    @registration.entries.where(person: ward).order(:created_at).last ||
      Intake::HouseholdMember.where(person: ward).joins(:entry).where(intake_entries: { registration_id: @registration.id }).first&.entry ||
      @registration.entries.create!(source: :link, person: ward, verified_at: Time.current, first_name: ward.first_name,
        last_name: ward.last_name, facts: { "team_ids" => @registration.membership_applications.where(person: ward).pluck(:team_id) })
  end

  def back_with(flash)
    redirect_back_or_to intake_registration_path(@registration), **flash
  end
end
