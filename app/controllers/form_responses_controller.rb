class FormResponsesController < InternalController
  before_action :require_feature
  before_action :set_response

  # GET /forms/1/responses/:subject_id
  def show
    authorize @response
    @submissions = @response.persisted? ? @response.form_submissions.includes(:submitted_by, :created_by, form_signatures: %i[ signer form_question ]).reverse : []
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
    @response.open_submission.discard!(by: current_person)
    redirect_to form_response_path(@form, @subject), notice: "The unsubmitted update was discarded. The submitted answers are unchanged.", status: :see_other
  end

  # POST /forms/1/responses/:subject_id/withdraw
  def withdraw
    authorize @response
    @response.active_submission.withdraw!(by: current_person)
    redirect_to form_response_path(@form, @subject), notice: "The response was withdrawn. Fill in the form again to replace it; it starts from the withdrawn answers.", status: :see_other
  end

  # POST /forms/1/responses/:subject_id/sign
  def sign
    authorize @response
    submission = @response.open_submission
    question = @form.signature_questions.detect { |candidate| candidate.id == params[:question_id] }
    error = if submission.nil? || question.nil?
      "There's nothing to sign."
    else
      submission.sign!(question, signer: current_person, typed_name: params[:typed_name], access: access,
        ip_address: request.remote_ip, user_agent: request.user_agent)
    end

    if error
      redirect_to form_response_path(@form, @subject), alert: error, status: :see_other
    elsif submission.reload.active?
      redirect_to form_response_path(@form, @subject), notice: "Thank you. It's signed, and the response is complete.", status: :see_other
    else
      redirect_to form_response_path(@form, @subject), notice: "Thank you. It's signed. It's still waiting for #{submission.waiting_for.to_sentence}.", status: :see_other
    end
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
      elsif @submission.missing_signatures.any? { |question| access.can_sign?(question) }
        "Your answers were submitted. Please sign below to finish."
      else
        "Your answers were submitted. It's waiting for #{@submission.waiting_for.to_sentence} before it's complete."
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
