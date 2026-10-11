class SignupSheetOrganizersController < InternalController
  before_action :set_signup_sheet

  # POST /signup_sheets/1/signup_sheet_organizers
  # Only people holding an organizer badge that reaches the sheet's team can
  # be added (SignupSheetOrganizer checks).
  def create
    person = Person.find_by(id: params.dig(:signup_sheet_organizer, :person_id))
    @organizer = authorize @signup_sheet.signup_sheet_organizers.build(person: person)

    if @organizer.save
      redirect_to edit_path, notice: "#{person.display_name} can now run this sheet.", status: :see_other
    else
      redirect_to edit_path, alert: "That organizer couldn't be added: #{@organizer.errors.full_messages.to_sentence}.", status: :see_other
    end
  end

  # DELETE /signup_sheets/1/signup_sheet_organizers/1
  def destroy
    @organizer = authorize @signup_sheet.signup_sheet_organizers.find(params[:id])
    if @signup_sheet.signup_sheet_organizers.count <= 1
      return redirect_to edit_path, alert: "A sheet needs at least one organizer. Add another before removing this one.", status: :see_other
    end

    @organizer.destroy!
    notice = "#{@organizer.person.display_name} no longer runs this sheet."
    if @signup_sheet.organizer?(current_user.person)
      redirect_to edit_path, notice: notice, status: :see_other
    else
      redirect_to signup_sheets_path, notice: notice, status: :see_other
    end
  end

  private
    def set_signup_sheet
      @signup_sheet = SignupSheet.find(params[:signup_sheet_id])
    end

    def edit_path
      edit_signup_sheet_path(@signup_sheet, anchor: "organizers")
    end
end
