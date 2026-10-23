# Who is on a form's printable list or counted on its tally, read for one
# viewer. One of:
#
# - asked: everyone the form asks, optionally narrowed to a team below its
#   audience
# - answered: people whose active answer to one yes/no, "Are you coming?",
#   choice, or multiple choice question, on any form, is one of the chosen
#   answers ("said Yes to Can you drive?", "said Yes or Maybe to the RSVP")
#
# Answers are read through FormReport, so both follow the same permissions
# as the results page. People whose answer the viewer can't read are counted
# (#hidden_count), never matched and never silently dropped.
class FormPopulation
  SOURCES = %w[ asked answered ].freeze
  CHOICE_TYPES = %w[ select multi_select ].freeze

  attr_reader :source, :viewer, :form, :team, :question, :answers

  # Builds a population for the form from request params. forms: the forms
  # the viewer may see results for; events: an Event scope the viewer may
  # see. With only an event (the event panel's link), it starts from who said
  # Yes to the event's "Are you coming?" question, if a form on it asks.
  # Links from before rev. 7 used `basis`; `expected` maps the same way.
  def self.from_params(params, viewer:, form:, forms:, events:)
    question = questions_from(forms).detect { |candidate| candidate.id == params[:question_id] }
    answers = question ? Array(params.dig(:answers, question.id)).compact_blank : []
    source = params[:who].presence_in(SOURCES)

    if source.nil? && params[:event_id].present? && [ nil, "expected" ].include?(params[:basis])
      event = events.find_by(id: params[:event_id])
      intent = event && EventForms.new(event, viewer: viewer).intent_question
      source, question, answers = "answered", intent, [ "Yes" ] if intent && forms.include?(intent.form)
    end

    new(source: source || "asked", viewer: viewer, form: form, team_id: params[:team_id], question: question, answers: answers)
  end

  # The questions a list can pick people by, on one form: yes/no and
  # "Are you coming?" first, then choice and multiple choice.
  def self.questions_for(form)
    questions = form.answerable_questions
    yes_no = questions.select { |question| question.intent? || question.value_type.type_boolean? }
    yes_no + questions.select { |question| !question.intent? && CHOICE_TYPES.include?(question.value_type.data_type) }
  end

  def self.questions_from(forms)
    forms.flat_map { |form| questions_for(form) }
  end

  # The form's team and the teams below it, for narrowing "asked".
  def self.team_choices(form)
    form&.team ? [ form.team ] + Team.where(id: form.team.all_descendant_ids).order(:name).to_a : []
  end

  # [label, value] pairs for a question's answers.
  def self.answer_choices(question)
    question.value_type.type_boolean? ? [ [ "Yes", "true" ], [ "No", "false" ] ] : question.choice_list.map { |choice| [ choice, choice ] }
  end

  def initialize(source:, viewer:, form:, team_id: nil, question: nil, answers: [])
    @source = source.presence_in(SOURCES) || "asked"
    @viewer = viewer
    @form = form
    @team = FormPopulation.team_choices(form).detect { |candidate| candidate.id == team_id }
    @question = question
    @answers = Array(answers).map(&:to_s)
  end

  # Whether there's enough to pick people.
  def ready?
    missing.nil?
  end

  # What's still to choose, if anything.
  def missing
    if source == "asked"
      "Choose a form." unless form
    elsif question.nil?
      "Choose a form and a question."
    elsif answers.empty?
      "Tick at least one answer."
    end
  end

  def people
    @people ||= (ready? ? pick_people : []).sort_by { |person| [ person.last_name.to_s.downcase, person.first_name.to_s.downcase ] }
  end

  def ids
    people.map(&:id)
  end

  # People whose answer to the question the viewer can't read ("answered").
  def hidden_count
    return 0 unless source == "answered" && ready?
    submitted = question.form.form_responses.joins(:active_submission)
    submitted = submitted.where("form_submissions.answers ? :key", key: question.key) unless question.value_type.type_boolean?
    answered_ids = submitted.pluck(:subject_id).to_set
    (answered_ids - readable_answer_ids).size
  end

  # For the printout, for example "22 who answered Yes or Maybe to "Are you
  # coming?" (Build Day RSVP)".
  def description
    count = people.size
    if source == "asked"
      "#{count} asked by #{form.title}#{" (#{team.name})" if team}"
    else
      chosen = answers.map { |answer| answer_label(answer) }.to_sentence(two_words_connector: " or ", last_word_connector: ", or ")
      "#{count} who answered #{chosen} to \"#{question.label}\" (#{question.form.title})"
    end
  end

  private

  def pick_people
    if source == "asked"
      FormReport.new(form, viewer: viewer, team: team).rows.select { |row| row.access.in_audience? }.map(&:person)
    else
      chosen = answers.map { |answer| question.value_type.type_boolean? ? answer == "true" : answer }
      answer_report.rows.select do |row|
        answered?(row) && Array(answer_report.answer(row, question)).intersect?(chosen)
      end.map(&:person)
    end
  end

  # An unticked yes/no is stored as no answer, so on a submitted response it
  # counts as No; other questions need a stored answer.
  def answered?(row)
    return false unless row.submission && answer_report.readable?(row, question)
    question.value_type.type_boolean? || row.submission.answers.key?(question.key)
  end

  def answer_report
    @answer_report ||= FormReport.new(question.form, viewer: viewer)
  end

  def readable_answer_ids
    answer_report.rows.select { |row| answered?(row) }.map { |row| row.person.id }.to_set
  end

  def answer_label(answer)
    return answer unless question.value_type.type_boolean?
    answer == "true" ? "Yes" : "No"
  end
end
