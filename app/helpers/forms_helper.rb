module FormsHelper
  Entry = Struct.new(:form, :subject, :response, :access, keyword_init: true) do
    def status
      response&.status || "not_started"
    end

    def to_do?
      form.open? && access.can_respond? && !%w[ complete waiting ].include?(status)
    end
  end

  STATUS_LABELS = {
    "not_started" => "Not started", "draft" => "In progress", "waiting" => "Waiting",
    "complete" => "Complete", "needs_reconfirmation" => "Needs re-confirmation", "withdrawn" => "Withdrawn"
  }.freeze

  STATUS_CLASSES = {
    "not_started" => "text-bg-secondary", "draft" => "text-bg-info", "waiting" => "text-bg-warning",
    "complete" => "text-bg-success", "needs_reconfirmation" => "text-bg-warning", "withdrawn" => "text-bg-dark"
  }.freeze

  SUBMISSION_STATUS_LABELS = {
    "draft" => "Draft (not submitted)", "pending" => "Submitted, waiting", "active" => "In effect", "superseded" => "Replaced",
    "withdrawn" => "Withdrawn", "discarded" => "Discarded"
  }.freeze

  PROFILE_MODE_LABELS = {
    nil => "Form only", "prefill" => "Filled in from profile", "update_profile" => "Updates profile"
  }.freeze

  # The forms a person answers for themselves and their wards: open forms,
  # and closed ones they have a response to.
  def form_entries_for(person)
    subjects = [ person ] + person.wards.order(:first_name).to_a
    Form.where(status: [ :open, :closed ]).includes(:team).order(:closes_at, :title).flat_map do |form|
      responses = form.form_responses.where(subject_id: subjects.map(&:id)).index_by(&:subject_id)
      subjects.filter_map do |subject|
        access = FormAccess.new(person, subject, form)
        next unless access.can_read?
        next if form.closed? && responses[subject.id].nil?
        Entry.new(form: form, subject: subject, response: responses[subject.id], access: access)
      end
    end
  end

  def forms_to_complete(person)
    form_entries_for(person).select(&:to_do?)
  end

  def form_status_badge(status)
    tag.span(STATUS_LABELS.fetch(status.to_s), class: "badge #{STATUS_CLASSES.fetch(status.to_s)}")
  end

  def form_state_badge(form)
    classes = { "draft" => "text-bg-secondary", "open" => "text-bg-success", "closed" => "text-bg-dark", "archived" => "text-bg-light" }
    tag.span(form.status.humanize, class: "badge #{classes.fetch(form.status)}")
  end

  def form_due(form)
    return "No deadline" unless form.closes_at
    form.open? ? "Due #{nice_datetime(form.closes_at)}" : "Closed #{nice_datetime(form.closes_at)}"
  end

  # The form's team and every team below it, for filters.
  def form_team_choices(form)
    [ form.team ] + Team.where(id: form.team.all_descendant_ids).order(:name).to_a
  end

  # Person fields the viewer can read for someone, as result columns.
  def form_profile_field_choices(viewer)
    PersonField.in_use.ordered.select { |field| field.readable_subjects_for(viewer).exists? }
  end

  # How the viewer relates to the subject, for the fill page header.
  def form_respondent_role(access)
    return "yourself" if access.viewer.id == access.subject.id
    return "as their guardian" if access.component?(:guardian)
    return "as their leader" if access.component?(:leaders)
    access.admin? ? "as an admin" : "for them"
  end

  def form_tallyable?(question)
    question.intent? || %w[ select multi_select boolean ].include?(question.value_type.data_type)
  end

  def form_answer_display(question, value)
    person_field_display(question.value_type, value)
  end

  def form_tally_label(value)
    case value
    when nil then "No answer"
    when true then "Yes"
    else value.to_s
    end
  end

  def form_markdown(text)
    sanitize(md(text))
  end

  def form_level_options
    person_field_level_options
  end

  def form_level_label(level)
    person_field_level_label(level)
  end

  # A simple_form input for one question. Inputs post under
  # form_response[answers][key].
  def form_question_input(form, question, value, error: nil)
    type = question.value_type
    name = "form_response[answers][#{question.key}]"
    options = { label: question.label, hint: question.body.presence, required: question.required?,
      input_html: { name: name, id: "form_question_#{question.key}" }, error: error }
    options[:wrapper_html] = { class: "is-invalid" } if error

    case type.data_type
    when "string", "phone", "email"
      options[:as] = { "string" => :string, "phone" => :tel, "email" => :email }.fetch(type.data_type)
      options[:input_html][:value] = value
    when "text"
      options[:as] = :text
      options[:input_html].merge!(value: value, rows: 3)
    when "integer"
      options[:as] = :integer
      options[:input_html][:value] = value
    when "date"
      options[:as] = :string
      options[:input_html].merge!(type: :date, value: value.respond_to?(:iso8601) ? value.iso8601 : value)
    when "boolean"
      options[:as] = :boolean
      options[:input_html][:checked] = ActiveModel::Type::Boolean.new.cast(value) == true
    when "select"
      options.merge!(as: :select, collection: person_field_choices(type, value), selected: value, include_blank: true)
    when "multi_select"
      options.merge!(as: :check_boxes, collection: person_field_choices(type, value), checked: Array(value))
      options[:input_html][:name] = "#{name}[]"
      options[:input_html].delete(:id)
      return hidden_field_tag("#{name}[]", "", id: nil) + form.input(question.key.to_sym, **options)
    end

    form.input question.key.to_sym, **options
  end

  def form_results_csv(report, fields)
    require "csv"
    questions = report.questions
    CSV.generate do |csv|
      csv << [ "Last name", "First name", "Status", "Version", "Submitted by", "Submitted at" ] + questions.map(&:label) + fields.map(&:name)
      report.rows.each do |row|
        submission = row.submission
        csv << [ row.person.last_name, row.person.first_name, STATUS_LABELS.fetch(row.status), submission&.number, submission&.submitted_by&.identifier_name, submission&.submitted_at&.iso8601 ] +
          questions.map { |question| form_csv_value(report.answer(row, question)) } +
          fields.map { |field| form_csv_value(report.profile(row, field)) }
      end
    end
  end

  def form_csv_value(value)
    case value
    when nil then nil
    when true then "Yes"
    when false then "No"
    when Array then value.join("; ")
    when Date then value.iso8601
    else value.to_s
    end
  end
end
