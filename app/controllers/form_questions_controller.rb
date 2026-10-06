class FormQuestionsController < InternalController
  before_action :require_feature
  before_action :set_form
  before_action :set_question, only: %i[ edit update destroy move ]

  # GET /forms/1/questions/new
  def new
    kind = params[:kind].presence_in(%w[ input heading statement acknowledgment signature intent ]) || "input"
    @question = authorize @form.form_questions.build(kind: kind, position: next_position, signer: kind == "signature" ? "guardian_if_minor" : nil,
      label: kind == "intent" ? "Are you coming?" : nil, required: kind == "intent")
  end

  # GET /forms/1/questions/1/edit
  def edit
  end

  # POST /forms/1/questions
  def create
    @question = authorize @form.form_questions.build(question_params.reverse_merge(position: next_position))

    if @question.save
      redirect_to edit_form_path(@form, tab: "questions"), notice: "Question was added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /forms/1/questions/1
  def update
    @question.assign_attributes(question_params)
    authorize @question
    if @question.save
      redirect_to edit_form_path(@form, tab: "questions"), notice: "Question was saved.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /forms/1/questions/1
  def destroy
    @question.destroy!
    redirect_to edit_form_path(@form, tab: "questions"), notice: "Question was removed. Answers already given stay in earlier submissions.", status: :see_other
  end

  # PATCH /forms/1/questions/1/move
  def move
    @question.move(params[:direction])
    redirect_to edit_form_path(@form, tab: "questions"), status: :see_other
  end

  private
    def set_form
      @form = Form.find(params[:form_id])
    end

    def set_question
      @question = authorize @form.form_questions.find(params[:id])
    end

    def next_position
      (@form.form_questions.maximum(:position) || -1) + 1
    end

    def require_feature
      redirect_to root_path, notice: "Forms are turned off" unless GatherPack::Features.enabled?(:forms)
    end

    def question_params
      permitted = [ :kind, :label, :body, :required, :person_field_id, :profile_mode, :read_permission, :write_permission,
        :choices_text, :min, :max, :pattern, :pattern_hint, :signer ]
      permitted += [ :key ] if @question.nil? || @question.new_record?
      permitted += [ :data_type ] if @question.nil? || @question.new_record? || !answered?
      attributes = params.require(:form_question).permit(*permitted)
      attributes[:read_permission] = nil if attributes.key?(:read_permission) && attributes[:read_permission].blank?
      attributes[:write_permission] = nil if attributes.key?(:write_permission) && attributes[:write_permission].blank?
      attributes[:person_field_id] = nil if attributes.key?(:person_field_id) && attributes[:person_field_id].blank?
      attributes
    end

    def answered?
      FormSubmission.joins(:form_response).where(form_responses: { form_id: @form.id }).where("answers ? :key", key: @question.key).exists?
    end
end
