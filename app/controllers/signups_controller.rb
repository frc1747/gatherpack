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
  end

  # POST /signup_sheets/1/signups
  def create
    @slot = find_slot(params.dig(:signup, :signup_slot_id))
    taker = chosen_person(:person_id) || default_taker
    authorize Signup.new(signup_slot: @slot, person: taker, signed_up_by: signer), :create?

    @signup = Signup.place!(slot: @slot, person: taker, signed_up_by: signer, on_behalf_of: chosen_person(:on_behalf_of_id), **detail_params)
    redirect_to signup_sheet_path(@signup_sheet), notice: "You're signed up for #{@slot.signup_position.name}.", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    @signup = e.record
    render :new, status: :unprocessable_entity
  end

  # GET /signup_sheets/1/signups/1/edit
  def edit
  end

  # PATCH/PUT /signup_sheets/1/signups/1
  def update
    changes = detail_params
    changes[:person] = chosen_person(:person_id) if signup_params[:person_id].present?
    changes[:on_behalf_of] = chosen_person(:on_behalf_of_id) if signup_params.key?(:on_behalf_of_id)

    @signup.change!(by: signer, **changes)
    redirect_to signup_sheet_path(@signup_sheet), notice: "Your sign-up was changed.", status: :see_other
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_entity
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
