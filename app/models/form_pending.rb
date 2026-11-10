# The people who still owe a form a complete response: everyone it asks
# whose response isn't complete. Remind uses it for the viewer's people and
# FormAutoReminderJob for everyone, so the two agree.
#
#   FormPending.new(form).people                    # everyone asked
#   FormPending.new(form, among: report.people)     # limited to these people
class FormPending
  attr_reader :form

  def initialize(form, among: nil)
    @form = form
    @among = among
  end

  def people
    people = form.audience
    people = people.where(id: @among.select(:id)) if @among
    done = form.form_responses.where(status: :complete).select(:subject_id)
    people.where.not(id: done).order(:last_name, :first_name).to_a
  end
end
