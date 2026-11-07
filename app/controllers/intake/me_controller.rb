# /join/:slug/me: a signed-in person's page for one registration. It shows
# their applications and their wards', and lets them finish what joining
# still needs (a birthday, a guardian, family members joining with them).
# It shows nobody else: a guardian acts for their wards, and anyone else's
# id is not found.
#
# Changes need the registration to be open, and either a self-service one
# or one the person signed up through. Only someone who doesn't need a
# guardian adds family members; only someone who does names a guardian,
# one request at a time. Both are limited per person per day.
class Intake::MeController < ApplicationController
  include Intake::PublicPages

  before_action :set_registration
  before_action :require_open_registration, only: %i[update_person add_guardian add_member]

  # GET /join/:slug/me
  def show
    @person = current_user.person
    @people = [ @person ] + @person.wards.order(:first_name).to_a
    @applications = MembershipApplication.where(registration: @registration, person: @people).includes(:team).order(:created_at).group_by(&:person_id)
    @guardian_rows = household_entry_rows
  end

  # PATCH /join/:slug/me/people/:person_id: a missing birthday, written
  # only where the birthday field's write level lets the signed-in person.
  # A birthday already on file is changed on the profile, not here.
  def update_person
    person = acting_for(params[:person_id])
    return back_with("A birthday is already on file. Ask a leader to change it.") if person.birthday
    return back_with("You can't add this birthday. Ask a leader.") unless birthday_writable?(person)

    birthday = Date.iso8601(params.dig(:person, :birthday).to_s)
    return back_with("Enter a birthday in the past.") if birthday > Date.current
    person.update!(birthday: birthday)
    redirect_to intake_me_path(@registration.slug), notice: "Saved."
  rescue Date::Error
    back_with("Enter a valid date.")
  end

  # POST /join/:slug/me/guardians: a young person names their guardian.
  def add_guardian
    person = current_user.person
    unless Intake.person_needs_guardian?(person) && !person.guardians.exists? &&
        person.membership_applications.pending.exists?(registration: @registration)
      return back_with("You don't need to name a guardian here.")
    end
    return back_with(Intake::PublicPages::TRY_AGAIN) if household_over_limit?("guardian", Intake.setting(:intake_rate_resend_per_day, 3))

    guardian = params.fetch(:guardian, {})
    row = Intake::Enrollment.new(entry_for(person)).name_guardian(ward: person, first_name: guardian[:first_name],
      last_name: guardian[:last_name], email: params[:guardian_email])
    Intake::GuardianEmailJob.perform_later(row.id)
    redirect_to intake_me_path(@registration.slug), notice: "Thanks. We've asked your guardian to confirm."
  rescue Intake::Enrollment::Refused => e
    back_with(e.message)
  end

  # POST /join/:slug/me/members: "Anyone else joining with you?"
  def add_member
    person = current_user.person
    return back_with("Ask a guardian to add family members.") if Intake.person_needs_guardian?(person)
    return back_with(Intake::PublicPages::TRY_AGAIN) if household_over_limit?("member", Intake.setting(:intake_rate_household_per_day, 10))

    member = params.fetch(:member, {})
    birthday = member[:birthday].presence && Date.iso8601(member[:birthday])
    teams = Array(member[:team_ids]).map(&:to_s) & @registration.apply_team_ids
    teams = @registration.apply_team_ids if teams.empty? && @registration.apply_team_ids.one?
    return redirect_to(intake_me_path(@registration.slug), alert: "Choose at least one team.") if teams.empty?

    ward = Intake::Enrollment.new(entry_for(person)).add_ward(adder: person, first_name: member[:first_name],
      last_name: member[:last_name], birthday: birthday, teams: teams)
    redirect_to intake_me_path(@registration.slug), notice: "Added #{ward.first_name}."
  rescue Intake::Enrollment::Refused => e
    redirect_to intake_me_path(@registration.slug), alert: e.message
  rescue Date::Error
    redirect_to intake_me_path(@registration.slug), alert: "Enter a valid date."
  end

  # DELETE /join/:slug/me/applications/:id
  def withdraw
    people = [ current_user.person ] + current_user.person.wards.to_a
    application = MembershipApplication.pending.where(registration: @registration, person: people).find(params[:id])
    application.destroy!
    redirect_to intake_me_path(@registration.slug), notice: "Withdrawn.", status: :see_other
  end

  private

  def set_registration
    @registration = Intake::Registration.find_by(slug: params[:slug].to_s)
    render "intake/join/closed", status: :not_found unless @registration
  end

  def require_open_registration
    signed_up = @registration.entries.exists?(person: current_user.person)
    return if @registration.open? && (@registration.self_service? || signed_up)
    back_with("This registration is closed.")
  end

  def back_with(alert)
    redirect_to intake_me_path(@registration.slug), alert: alert
  end

  def household_over_limit?(name, limit)
    intake_over_limit?("me-#{name}", current_user.person.id, to: limit, within: 1.day)
  end

  # The birthday is a person field; its write level decides who may set it.
  def birthday_writable?(person)
    field = PersonField.find_by(system_source: "birthday")
    field.nil? || PersonFieldAccess.new(current_user.person, person).writable?(field)
  end

  # The signed-in person, or one of their wards. Anyone else isn't found.
  def acting_for(id)
    person = current_user.person
    return person if [ person.id, person.neat_id ].include?(id)
    person.wards.find(id)
  end

  # The person's household on this registration: the entry they verified,
  # or a new one (someone who signed in rather than signing up).
  def entry_for(person)
    @registration.entries.verified.where(person: person).order(:created_at).last ||
      @registration.entries.create!(source: :link, person: person, verified_at: Time.current, first_name: person.first_name,
        last_name: person.last_name, facts: { "team_ids" => @registration.apply_team_ids })
  end

  def household_entry_rows
    entries = @registration.entries.verified.where(person: current_user.person)
    Intake::HouseholdMember.guardian.where(entry: entries).to_a
  end
end
