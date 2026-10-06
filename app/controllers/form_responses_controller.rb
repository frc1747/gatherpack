class FormResponsesController < InternalController
  before_action :require_feature
  before_action :set_response

  # GET /forms/1/responses/:subject_id
  def show
    authorize @response
    @submissions = @response.persisted? ? @response.form_submissions.includes(:submitted_by, :created_by).reverse : []
  end

  # GET /forms/1/responses/:subject_id/edit
  def edit
    authorize @response
    # Nothing is saved until Save or Submit, so Cancel leaves no draft behind.
    @submission = @response.open_submission ||
      FormSubmission.new(form_response: @response, answers: @response.starting_answers, form_version: @form.content_version, based_on: @response.active_submission)
    @errors = {}
  end

  # PATCH /forms/1/responses/:subject_id
  # Saves the answers, and submits them when the Submit button was pressed.
  def update
    authorize @response
    @errors = {}

    FormResponse.transaction do
      @response.save! if @response.new_record?
      @submission = @response.start_submission!(current_person)
      @errors = @submission.assign_answers(params.dig(:form_response, :answers)&.to_unsafe_h || {}, access)
      raise ActiveRecord::Rollback if @errors.any?

      @submission.save!
      @response.sync_status!
    end
    return render_edit_with_errors if @errors.any?

    if params[:submit].present?
      @errors = @submission.submit!(current_person, access)
      return render_edit_with_errors if @errors.any?

      redirect_to form_response_path(@form, @subject), notice: submitted_notice, status: :see_other
    else
      redirect_to edit_form_response_path(@form, @subject), notice: "Your answers were saved. They aren't submitted yet.", status: :see_other
    end
  end

  # POST /forms/1/responses/:subject_id/submit
  def submit
    authorize @response
    @submission = @response.open_submission
    @errors = @submission.submit!(current_person, access)
    if @errors.any?
      redirect_to edit_form_response_path(@form, @subject), alert: "Some required questions need an answer first.", status: :see_other
    else
      redirect_to form_response_path(@form, @subject), notice: submitted_notice, status: :see_other
    end
  end

  # POST /forms/1/responses/:subject_id/discard
  def discard
    authorize @response
    @response.open_submission.discard!
    redirect_to form_response_path(@form, @subject), notice: "The unsubmitted update was discarded. The submitted answers are unchanged.", status: :see_other
  end

  # POST /forms/1/responses/:subject_id/withdraw
  def withdraw
    authorize @response
    @response.active_submission.withdraw!
    redirect_to form_response_path(@form, @subject), notice: "The response was withdrawn. Fill in the form again to replace it; it starts from the withdrawn answers.", status: :see_other
  end

  private
    def set_response
      @form = Form.find(params[:form_id])
      @subject = Person.find(params[:subject_id])
      @response = @form.form_responses.includes(:form_submissions).find_or_initialize_by(subject: @subject)
    end

    def current_person
      current_user.person
    end

    def access
      @access ||= FormAccess.new(current_person, @subject, @form)
    end

    def submitted_notice
      if @submission.active?
        "Thank you. Your response was submitted."
      else
        "Your answers were submitted. Some questions still need an answer from someone else before this is complete."
      end
    end

    def render_edit_with_errors
      flash.now[:alert] = "Please check the answers marked below."
      render :edit, status: :unprocessable_entity
    end

    def require_feature
      redirect_to root_path, notice: "Forms are turned off" unless GatherPack::Features.enabled?(:forms)
    end
end
