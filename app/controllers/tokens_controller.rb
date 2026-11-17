class TokensController < InternalController
  before_action :set_token, only: %i[ show edit update destroy ]

  # GET /tokens
  def index
    @q = policy_scope(Token).ransack(params[:q], auth_object: current_user)
    @q.sorts = "value asc" if @q.sorts.empty?
    @tokens = @q.result(distinct: true).order(value: :asc).page(params[:page])
  end

  # GET /tokens/1
  def show
  end

  # GET /tokens/new
  def new
    @token = authorize Token.new
  end

  # GET /tokens/1/edit
  def edit
  end

  # POST /tokens
  def create
    @token = authorize Token.new, :new?
    return unless assign_token_params(:new)

    authorize @token

    @other_token = Token.find_by_rfid(@token.value)
    if @other_token
      redirect_to edit_token_path(@other_token), notice: "Token with the same value already exists."
      return
    end

    if @token.save
      redirect_to @token, notice: "Token was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /tokens/1
  def update
    # Authorize again once the new holder is in place: set_token only checked
    # the card as it was.
    return unless assign_token_params(:edit)

    authorize @token

    if @token.save
      redirect_to @token, notice: "Token was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /tokens/1
  def destroy
    @token.destroy!
    redirect_to tokens_url, notice: "Token was successfully destroyed.", status: :see_other
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_token
      @token = authorize policy_scope(Token).find(params[:id])
    end

    # Assigns the form's values to @token, or renders the form again when the
    # holder's id doesn't match any record.
    def assign_token_params(template)
      @token.assign_attributes(token_params)
      true
    rescue ArgumentError, NeatIds::Error
      @token.errors.add(:tokenable_nid, "doesn't match anyone")
      render template, status: :unprocessable_entity
      false
    end

    # Only allow a list of trusted parameters through.
    def token_params
      params.require(:token).permit(:value, :tokenable_nid)
    end
end
