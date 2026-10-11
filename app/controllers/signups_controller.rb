# Members taking, changing and cancelling places on a sheet. Every placement
# goes through Signup.place! or Signup#change!, which check capacity, rules
# and who may be signed up; organizers add and move people from the roster.
class SignupsController < InternalController
  before_action :set_signup_sheet
  before_action :set_signup, only: %i[ edit update destroy ]

  helper_method :taker_choices, :on_behalf_of_choices

  # GET /signup_sheets/1/signups/new?slot_id=...
  def new
    @slot = find_slot(params[:slot_id])
    @signup = Signup.new(signup_slot: @slot, person: default_taker, signed_up_by: signer)
    authorize @signup, :create?

    respond_to do |format|
      format.html
      # The on-behalf-of picker's type-to-search results.
      format.turbo_stream { @on_behalf_of_matches = on_behalf_of_matches(params[:q], @signup.person) }
    end
  end

  # POST /signup_sheets/1/signups
  def create
    @slot = find_slot(params.dig(:signup, :signup_slot_id))
    taker = chosen_person(:person_id) || default_taker
    on_behalf_of = chosen_person(:on_behalf_of_id) || taker
    @signup = authorize Signup.new(signup_slot: @slot, person: taker, signed_up_by: signer, on_behalf_of: on_behalf_of, **detail_params), :create?
    return render_search(:new) if params[:find].present?

    check_choices!(@signup)

    @signup = Signup.place!(slot: @slot, person: taker, signed_up_by: signer, on_behalf_of: on_behalf_of, **detail_params)
    redirect_to signup_sheet_path(@signup_sheet), notice: "You're signed up for #{@slot.signup_position.name}.", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    @signup = e.record
    render :new, status: :unprocessable_entity, formats: :html
  end

  # GET /signup_sheets/1/signups/1/edit
  def edit
  end

  # PATCH/PUT /signup_sheets/1/signups/1
  def update
    changes = detail_params
    changes[:person] = chosen_person(:person_id) if signup_params[:person_id].present?
    if signup_params.key?(:on_behalf_of_id)
      changes[:on_behalf_of] = chosen_person(:on_behalf_of_id) || changes[:person] || @signup.person
    elsif changes[:person] && changes[:person] != @signup.person
      changes[:on_behalf_of] = changes[:person]
    end

    @signup.assign_attributes(changes)
    return render_search(:edit) if params[:find].present?

    check_choices!(@signup)
    @signup.change!(by: signer, **changes)
    redirect_to signup_sheet_path(@signup_sheet), notice: "Your sign-up was changed.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_entity, formats: :html
  end

  # DELETE /signup_sheets/1/signups/1
  # Cancels the sign-up; it stays on the roster as cancelled.
  def destroy
    @signup.cancel!
    redirect_to signup_sheet_path(@signup_sheet), notice: "Your sign-up was cancelled.", status: :see_other
  end

  private
    def set_signup_sheet
      @signup_sheet = authorize SignupSheet.find(params[:signup_sheet_id]), :show?
    end

    def set_signup
      @signup = @signup_sheet.signups.find(params[:id])
      @slot = @signup.signup_slot
      authorize @signup, action_name == "destroy" ? :destroy? : :update?
    end

    def find_slot(id)
      @signup_sheet.signup_slots.where(disabled: false).includes(:signup_position, :event).find(id)
    end

    def signer
      current_user.person
    end

    # The signer if they can take the place, or else the first person they
    # can sign up.
    def default_taker
      taker_choices.find { |taker| taker.id == signer&.id } || taker_choices.first || signer
    end

    # Who the signer may sign up to take the place.
    def taker_choices
      @taker_choices ||= @signup_sheet.takers_for(signer).order(:last_name, :first_name).to_a
    end

    # Everyone a sign-up by this signer could be on behalf of, for any of
    # the takers. Signup.place! checks the pair that's picked.
    def on_behalf_of_choices
      @on_behalf_of_choices ||= begin
        ids = taker_choices.flat_map { |taker| @signup_sheet.on_behalf_of_choices_for(signer, taker).ids }
        Person.where(id: ids).order(:last_name, :first_name).to_a
      end
    end

    # The member pages only take people the signer could sign up themselves,
    # organizers included (Signup.place! lets organizers place anyone; they
    # do that from the roster). Raises ActiveRecord::RecordInvalid with the
    # reason.
    def check_choices!(signup)
      new_taker = signup.new_record? || signup.person_id_changed?
      problems = []
      problems << "You can't sign up #{signup.person.identifier_name} on this sheet" if new_taker && taker_choices.exclude?(signup.person)
      if (new_taker || signup.on_behalf_of_id_changed?) && !@signup_sheet.on_behalf_of_choices_for(signer, signup.person).exists?(id: signup.on_behalf_of_id)
        problems << "You can't sign up on behalf of #{signup.on_behalf_of.identifier_name}"
      end
      problems.each { |problem| signup.errors.add(:base, problem) }
      raise ActiveRecord::RecordInvalid, signup if problems.any?
    end

    # People the sign-up could be on behalf of whose names match what was
    # typed, a few letters at least, for the picker on sheets open to anyone.
    def on_behalf_of_matches(query, taker)
      query = query.to_s.strip
      return Person.none if query.length < 2

      @signup_sheet.on_behalf_of_choices_for(signer, taker)
        .ransack(first_name_or_last_name_or_display_name_cont: query).result
        .order(:last_name, :first_name).limit(10)
    end

    # Without JavaScript the picker is a plain search: Find shows the form
    # again with the matches to choose from, saving nothing.
    def render_search(template)
      @on_behalf_of_matches = on_behalf_of_matches(params[:on_behalf_of_search], @signup.person).to_a
      render template, formats: :html
    end

    def chosen_person(key)
      id = signup_params[key]
      Person.find(id) if id.present?
    end

    # The fields that fit the position's kind: extra people for people
    # positions, a quantity for items.
    def detail_params
      details = signup_params.slice(:answer, :note).to_h.symbolize_keys
      if @slot.items?
        details[:quantity] = signup_params[:quantity]
      else
        details[:extra_people] = signup_params[:extra_people].presence || 0
        details[:extra_names] = details[:extra_people].to_i.positive? ? signup_params[:extra_names] : nil
      end
      details
    end

    def signup_params
      params.fetch(:signup, {}).permit(:signup_slot_id, :person_id, :on_behalf_of_id, :extra_people, :extra_names, :quantity, :answer, :note)
    end
end
