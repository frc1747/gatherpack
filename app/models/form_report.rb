# Reads a form's answers for one viewer, alongside current profile data,
# applying that viewer's access to every cell. The results page uses it, and
# dynamic Pages should too: a Page's code runs for whoever views it.
#
#   report = FormReport.new(Form.find_by!(key: "meal_choices_2027"), viewer: current_person)
#   report.rows.each do |row|
#     report.answer(row, "sandwich")                 # nil if the viewer can't see it
#     report.profile(row, "dietary_restrictions")    # current profile value, same rule
#   end
class FormReport
  Row = Struct.new(:person, :response, :submission, :access) do
    # People no longer asked keep their response, listed apart.
    def status
      return "no_longer_asked" unless access.in_audience?
      response_status
    end

    def response_status
      response&.status || "not_started"
    end
  end

  STATUSES = %w[ not_started draft waiting complete needs_reconfirmation withdrawn no_longer_asked ].freeze

  attr_reader :form, :viewer, :version

  # version: :active (the default) reads each person's active submission;
  # :latest reads a draft or pending update instead where there is one.
  # only: limits the rows to these people (ids), such as an event's
  # expected or checked-in people.
  # shared_totals: counts everyone asked, for a viewer who may see the totals
  # but not the answers (Form#totals_visible_to?). Only
  # Form#shared_totals_questions are counted; use it for #tally only.
  def initialize(form, viewer:, team: nil, version: :active, only: nil, shared_totals: false)
    @form = form
    @viewer = viewer
    @team = team
    @version = version
    @only = only
    @shared_totals = shared_totals
  end

  def shared_totals?
    @shared_totals
  end

  def people
    people = shared_totals? ? form.audience : form.readable_subjects_for(viewer)
    people = people.where(id: @team.descendant_people.select(:id)) if @team
    people = people.where(id: @only.to_a) if @only
    people.order(:last_name, :first_name)
  end

  def rows
    @rows ||= begin
      list = people.to_a
      asked = form.audience.where(id: list.map(&:id)).ids.to_set
      responses = form.form_responses.where(subject_id: list.map(&:id)).includes(form_submissions: { form_signatures: :signer }).index_by(&:subject_id)
      list.map do |person|
        response = responses[person.id]
        submission = response && (version == :latest ? response.open_submission || response.active_submission : response.active_submission)
        access = FormAccess.new(viewer, person, form, in_audience: asked.include?(person.id), has_response: response.present?)
        Row.new(person, response, submission, access)
      end
    end
  end

  def questions
    shared_totals? ? form.shared_totals_questions : form.answerable_questions
  end

  def question(key)
    form.form_questions.detect { |question| question.key == key.to_s } || raise(ArgumentError, "No question #{key} on #{form.key}")
  end

  def readable?(row, question)
    return form.shared_totals_questions.include?(question) if shared_totals?
    row.access.question_readable?(question)
  end

  def answer(row, key)
    question = key.is_a?(FormQuestion) ? key : question(key)
    return nil unless row.submission && readable?(row, question)
    row.submission.answer(question)
  end

  def profile(row, field_key)
    field = field_key.is_a?(PersonField) ? field_key : PersonField.find_by!(key: field_key.to_s)
    row.access.field_access.readable?(field) ? row.person.field_value(field) : nil
  end

  # An "updates profile" answer that no longer matches the profile.
  def changed_since_signed?(row, key)
    question = key.is_a?(FormQuestion) ? key : question(key)
    return false unless row.submission && readable?(row, question)
    row.submission.profile_changed?(question)
  end

  def status_counts
    STATUSES.index_with { |status| rows.count { |row| row.status == status } }
  end

  # { choice => count } over the rows' readable answers, plus nil for no
  # answer. For choice, multiple choice, yes/no, and intent questions.
  def tally(key)
    question = key.is_a?(FormQuestion) ? key : question(key)
    counted = rows.select { |row| readable?(row, question) }
    choices = question.value_type.type_boolean? ? [ true ] : question.value_type.choice_list
    counts = choices.index_with { 0 }
    counts[nil] = 0
    counted.each do |row|
      value = row.submission&.answers&.key?(question.key) ? row.submission.answer(question) : nil
      Array(value.nil? ? [ nil ] : value).each { |choice| counts[choice] = counts.fetch(choice, 0) + 1 }
    end
    counts
  end
end
