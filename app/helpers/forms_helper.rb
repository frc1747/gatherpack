module FormsHelper
  Entry = Struct.new(:form, :subject, :response, :access, keyword_init: true) do
    def status
      response&.status || "not_started"
    end

    # Something for the viewer to do: fill in, continue, update for a
    # re-confirmation, or sign.
    def to_do?
      return needs_viewer_signature? if status == "waiting"
      form.open? && access.in_audience? && access.can_respond? && status != "complete" && viewer_can_act?
    end

    # Whether there's anything on the form the viewer could fill in or
    # sign. A student can't act on a form only their parent fills in.
    def viewer_can_act?
      questions = form.form_questions.to_a
      return true if questions.none? { |question| question.answerable? || question.signature? }
      questions.any? { |question| access.question_writable?(question) || (question.signature? && access.can_sign?(question)) }
    end

    # Left for someone else: open and asked, but nothing the viewer can do.
    def for_someone_else?
      form.open? && access.in_audience? && status != "complete" && !to_do? && !waiting_on_others?
    end

    def needs_viewer_signature?
      submission = response&.open_submission
      submission&.pending? && submission.missing_signatures.any? { |question| access.can_sign?(question) }
    end

    # Waiting for an answer or signature from someone other than the viewer.
    def waiting_on_others?
      status == "waiting" && !needs_viewer_signature?
    end
  end

  PersonFormSections = Struct.new(:to_do, :waiting, :complete, :earlier, keyword_init: true) do
    def empty?
      to_h.values.all?(&:empty?)
    end
  end

  STATUS_LABELS = {
    "not_started" => "Not started", "draft" => "In progress", "waiting" => "Waiting",
    "complete" => "Complete", "needs_reconfirmation" => "Needs re-confirmation", "withdrawn" => "Withdrawn",
    "no_longer_asked" => "No longer asked"
  }.freeze

  STATUS_CLASSES = {
    "not_started" => "text-bg-secondary", "draft" => "text-bg-info", "waiting" => "text-bg-warning",
    "complete" => "text-bg-success", "needs_reconfirmation" => "text-bg-warning", "withdrawn" => "text-bg-dark",
    "no_longer_asked" => "text-bg-light"
  }.freeze

  SIGNER_LABELS = {
    "guardian_if_minor" => "A guardian; or the person themselves once their birthday on file shows they're of age",
    "guardian" => "A guardian", "subject" => "The person themselves", "leader" => "A leader, recording a paper form"
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

  # Where clicking an entry goes: straight to the form when there's
  # something to fill in, otherwise the response page (to sign, or to see
  # what was submitted).
  def form_entry_path(entry)
    if entry.to_do? && !entry.needs_viewer_signature?
      edit_form_response_path(entry.form, entry.subject)
    else
      form_response_path(entry.form, entry.subject)
    end
  end

  LeaderTodo = Struct.new(:form, :people, keyword_init: true)

  # For forms that ask for it (leader_todo), the submitted responses waiting
  # on this person as a leader: an answer only they can give, or a paper
  # signature. Their own and their children's forms are in the personal list.
  def leader_todos(person)
    own = [ person.id ] + person.wards.ids
    Form.where(status: %i[ open closed ], leader_todo: true).includes(:form_questions, :form_badge_grants).order(:closes_at, :title).filter_map do |form|
      next unless policy(form).show?

      report = FormReport.new(form, viewer: person)
      people = report.rows.filter_map do |row|
        submission = row.response&.open_submission
        next unless submission&.pending? && !own.include?(row.person.id)
        waiting_on_viewer = submission.missing_questions.any? { |question| row.access.question_writable?(question) } ||
          submission.missing_signatures.any? { |question| row.access.signing_role(question) == :leader }
        row.person if waiting_on_viewer
      end
      LeaderTodo.new(form: form, people: people) if people.any?
    end
  end

  def forms_to_complete(person)
    form_entries_for(person).select(&:to_do?)
  end

  # Whether the viewer gets the Forms tab on someone's profile: themselves,
  # a guardian, a leader of theirs, or an admin.
  def person_forms_tab?(person, viewer = current_user.person)
    return false unless GatherPack::Features.enabled?(:forms) && viewer
    viewer.id == person.id || viewer.admin? || viewer.wards.where(id: person.id).exists? || viewer.can_manage(person)
  end

  # The forms of the person's wards (their children) the viewer can see:
  # open forms, and earlier ones with a response. For the "For their
  # children" section of a parent's Forms tab.
  def ward_form_entries(person, viewer)
    wards = person.wards.order(:first_name, :last_name).to_a
    return [] if wards.empty?

    responses = FormResponse.where(subject_id: wards.map(&:id)).includes(form_submissions: :form_signatures).index_by { |response| [ response.form_id, response.subject_id ] }
    Form.where(status: %i[ open closed ]).includes(:team, :form_badge_grants).order(:closes_at, :title).flat_map do |form|
      wards.filter_map do |ward|
        response = responses[[ form.id, ward.id ]]
        next if form.closed? && response.nil?

        access = FormAccess.new(viewer, ward, form, has_response: response.present?)
        next unless access.can_read? && (access.in_audience? || response)
        Entry.new(form: form, subject: ward, response: response, access: access)
      end
    end
  end

  # Every form about the person the viewer can see, in the profile tab's
  # sections.
  def person_form_entries(person, viewer)
    responses = FormResponse.where(subject: person).includes(form_submissions: :form_signatures).index_by(&:form_id)
    sections = PersonFormSections.new(to_do: [], waiting: [], complete: [], earlier: [])
    Form.where.not(status: :draft).includes(:team, :form_badge_grants).order(:closes_at, :title).each do |form|
      response = responses[form.id]
      access = FormAccess.new(viewer, person, form, has_response: response.present?)
      next unless access.can_read?
      next if form.archived? && response.nil?

      entry = Entry.new(form: form, subject: person, response: response, access: access)
      section = if entry.needs_viewer_signature? then :to_do
      elsif entry.status == "waiting" || entry.for_someone_else? then :waiting
      elsif !form.open? || !access.in_audience? then (response ? :earlier : nil)
      elsif entry.status == "complete" then :complete
      else :to_do
      end
      sections[section] << entry if section
    end
    sections
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
    return "as the form's organizer" if access.creator?
    access.admin? ? "as an admin" : "for them"
  end

  def form_tallyable?(question)
    question.intent? || %w[ select multi_select boolean ].include?(question.value_type.data_type)
  end

  def form_answer_display(question, value)
    return (value == true ? "#{i("square-check")} Ticked".html_safe : "Not ticked") if question.acknowledgment?
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

  # Who fills in a question someone can't, in words for the person reading.
  def form_writer_phrase(level)
    { "guardians" => "a parent or guardian", "leaders" => "a leader", "admin" => "an admin", "self" => "the person themselves" }.fetch(level.to_s, "someone else")
  end

  # Who an entry the viewer can't act on is left for.
  def form_left_for(entry)
    question = entry.form.form_questions.detect { |candidate| candidate.answerable? && !entry.access.question_writable?(candidate) }
    question ? form_writer_phrase(question.effective_write_permission) : "someone else"
  end

  def form_level_label(level)
    person_field_level_label(level)
  end

  # A tick box with its label beside it and any detail text indented under
  # the label (a hanging indent). Read-only boxes are shown disabled. The
  # app's stylesheet unfloats .form-check-input, so this uses flex rather
  # than Bootstrap's .form-check.
  def form_acknowledgment(question, value, writable:, error: nil)
    name = "form_response[answers][#{question.key}]"
    id = "form_question_#{question.key}"
    checked = ActiveModel::Type::Boolean.new.cast(value) == true
    box = check_box_tag(name, "1", checked, id: id, disabled: !writable, class: "form-check-input flex-shrink-0 mt-1#{" is-invalid" if error}")
    box = hidden_field_tag(name, "0", id: nil) + box if writable

    tag.div(class: "d-flex gap-2 mb-2 form-acknowledgment") do
      box + tag.div do
        safe_join([
          label_tag(id, question.label, class: "form-check-label#{" text-body-secondary" unless writable}"),
          (tag.div(form_markdown(question.body), class: "form-text mt-1 mb-0 form-acknowledgment-detail") if question.body.present?),
          (tag.div(error, class: "invalid-feedback d-block") if error)
        ].compact)
      end
    end
  end

  # A simple_form input for one question. Inputs post under
  # form_response[answers][key].
  def form_question_input(form, question, value, error: nil)
    type = question.value_type
    name = "form_response[answers][#{question.key}]"
    # An acknowledgment's text is shown above its tick box instead.
    options = { label: question.label, hint: (question.body.presence unless question.acknowledgment?), required: question.required?,
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
      # The Bootstrap boolean wrapper has no error slot, so show it here.
      return form.input(question.key.to_sym, **options) + (error ? tag.div(error, class: "invalid-feedback d-block mt-n2 mb-3") : "".html_safe)
    when "select"
      if question.intent?
        options.merge!(as: :radio_buttons, collection: FormQuestion::INTENT_CHOICES, checked: value.to_s, item_wrapper_class: "form-check form-check-inline")
        options[:input_html].delete(:id)
        return form.input(question.key.to_sym, **options)
      end
      options.merge!(as: :select, collection: person_field_choices(type, value), selected: value, include_blank: true)
    when "multi_select"
      options.merge!(as: :check_boxes, collection: person_field_choices(type, value), checked: Array(value))
      options[:input_html][:name] = "#{name}[]"
      options[:input_html].delete(:id)
      return hidden_field_tag("#{name}[]", "", id: nil) + form.input(question.key.to_sym, **options)
    end

    form.input question.key.to_sym, **options
  end

  # "Jo Parent (guardian), Oct 3"
  def form_signed_summary(submission)
    submission.standing_signatures.sort_by(&:signed_at).map do |signature|
      "#{signature.signer.identifier_name}#{" (paper)" if signature.signed_as_leader?}, #{nice_date(signature.signed_at)}"
    end.join("; ")
  end

  def form_results_csv(report, fields)
    require "csv"
    questions = report.questions
    CSV.generate do |csv|
      csv << [ "Last name", "First name", "Status", "Version", "Form version", "Submitted by", "Submitted at", "Signed by", "Signed at" ] + questions.map(&:label) + fields.map(&:name)
      report.rows.each do |row|
        submission = row.submission
        signatures = submission ? submission.standing_signatures.sort_by(&:signed_at) : []
        csv << [ row.person.last_name, row.person.first_name, STATUS_LABELS.fetch(row.status), submission&.number, submission&.form_version, submission&.submitted_by&.identifier_name, submission&.submitted_at&.iso8601,
          signatures.map { |signature| signature.signer.identifier_name }.join("; ").presence, signatures.map { |signature| signature.signed_at.iso8601 }.join("; ").presence ] +
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
