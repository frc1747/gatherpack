# One version of a response, with the form's text as it was submitted and
# the signatures on it: what exactly someone signed.
class FormSubmissionsController < InternalController
  before_action :require_feature

  # GET /forms/1/responses/:subject_id/submissions/1
  def show
    @form = Form.find(params[:form_id])
    @subject = Person.find(params[:response_subject_id])
    @response = @form.form_responses.find_by!(subject: @subject)
    authorize @response, :show?
    @submission = @response.form_submissions.includes(form_signatures: %i[ signer revoked_by form_question ]).find(params[:id])
    @access = FormAccess.new(current_user.person, @subject, @form)
  end

  private
    def require_feature
      redirect_to root_path, notice: "Forms are turned off" unless GatherPack::Features.enabled?(:forms)
    end
end
