class SignupPositionsController < InternalController
  before_action :set_signup_sheet
  before_action :set_signup_position, only: %i[ edit update destroy ]

  # GET /signup_sheets/1/signup_positions/new
  def new
    @signup_position = authorize @signup_sheet.signup_positions.build
  end

  # GET /signup_sheets/1/signup_positions/1/edit
  def edit
  end

  # POST /signup_sheets/1/signup_positions
  def create
    @signup_position = authorize @signup_sheet.signup_positions.build(signup_position_params)

    if @signup_position.save
      redirect_to edit_signup_sheet_signup_position_path(@signup_sheet, @signup_position),
        notice: "#{@signup_position.name} added. Add rules below if only some people can take it.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /signup_sheets/1/signup_positions/1
  # With move=up or move=down, swaps the position with its neighbor.
  def update
    if params[:move].present?
      move(params[:move])
      redirect_to edit_signup_sheet_path(@signup_sheet, anchor: "positions"), status: :see_other
    elsif kind_change_refused?
      render :edit, status: :unprocessable_entity
    elsif @signup_position.update(signup_position_params)
      redirect_to edit_signup_sheet_path(@signup_sheet, anchor: "positions"), notice: "#{@signup_position.name} saved.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /signup_sheets/1/signup_positions/1
  def destroy
    if @signup_position.destroy
      redirect_to edit_signup_sheet_path(@signup_sheet, anchor: "positions"), notice: "#{@signup_position.name} removed.", status: :see_other
    else
      redirect_to edit_signup_sheet_path(@signup_sheet, anchor: "positions"), alert: @signup_position.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private
    def set_signup_sheet
      @signup_sheet = SignupSheet.find(params[:signup_sheet_id])
    end

    def set_signup_position
      @signup_position = authorize @signup_sheet.signup_positions.find(params[:id])
    end

    # Renumbers the sheet's positions with this one swapped with the one
    # above or below it.
    def move(direction)
      positions = @signup_sheet.signup_positions.to_a
      index = positions.index(@signup_position)
      other = direction == "up" ? index - 1 : index + 1
      return if other.negative? || other >= positions.size

      positions[index], positions[other] = positions[other], positions[index]
      SignupPosition.transaction do
        positions.each_with_index { |position, number| position.update!(position: number) unless position.position == number }
      end
    end

    # Usage and caps count places for people and quantities for items, so
    # the kind can't change once anyone is signed up.
    def kind_change_refused?
      kind = signup_position_params[:kind]
      return false if kind.blank? || kind == @signup_position.kind || !@signup_position.signups.live.exists?

      @signup_position.assign_attributes(signup_position_params.except(:kind))
      @signup_position.errors.add(:kind, "can't change while people are signed up")
      true
    end

    def signup_position_params
      params.require(:signup_position).permit(:name, :description, :kind, :unit, :capacity, :question, :question_required)
    end
end
